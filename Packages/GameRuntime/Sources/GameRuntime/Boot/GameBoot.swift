#if os(iOS)
  import Darwin
  import GameRuntimeABI
  import LauncherFeature
  import UIKit

  /// Start-up order: the game's `main` asks for the application; UIKit launches instead and shows
  /// the launcher, so the launch watchdog sees a responsive app. Play prepares the data and, from
  /// a run-loop timer once the loading screen is on display, enters `main` again on a 64 MB stack;
  /// `main` then runs the game on the main thread for the rest of the process.
  enum GameBoot {
    nonisolated(unsafe) private static var uikitStarted = false
    @MainActor private static var launched = false
    private static let gameMain = MachOImage.main.entryPoint

    /// Whether `+[NSApplication sharedApplication]` was called from the start of the game's
    /// `main` before UIKit launched.
    static func isCalledFromGameMain() -> Bool {
      guard !uikitStarted, let gameMain else { return false }
      var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 8)
      let count = Int(backtrace(&frames, Int32(frames.count)))
      return frames.prefix(count).contains { frame in
        frame.map { (0..<0x80).contains(gameMain.distance(to: UnsafeRawPointer($0))) } ?? false
      }
    }

    static func startUIKit() -> Never {
      uikitStarted = true
      RuntimeLog.write("game main() reached sharedApplication; launching UIKit first")
      UIApplicationMain(
        CommandLine.argc, CommandLine.unsafeArgv, nil,
        NSStringFromClass(GameApplicationDelegate.self))
      exit(0)
    }

    @MainActor static func makeLauncher() -> UIViewController {
      let screen = ScreenMetrics.refresh().size
      let client = LauncherClient(play: { try play(mode: DisplayMode(index: $0)) })
      return makeLauncherViewController(
        resolutions: DisplayMode.all.map {
          $0.settingName(screen: screen).replacingOccurrences(of: "x", with: " × ")
        },
        selectedResolution: DisplayMode.selected.index, icon: icon, client: client)
    }

    /// The app icon, the original game icon staged at build time.
    @MainActor static var icon: UIImage {
      let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
      let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
      guard let name = (primary?["CFBundleIconFiles"] as? [String])?.last,
        let icon = UIImage(named: name)
      else { preconditionFailure("the app icon is missing from the bundle") }
      return icon
    }

    @MainActor private static func play(mode: DisplayMode) throws {
      guard !launched else { return }
      try GamePreparation.prepareData()
      let screen = ScreenMetrics.refresh()
      try GamePreparation.applySettings(resolution: mode.settingName(screen: screen.size))
      DisplayMode.select(mode)
      launched = true
      guard let window = GameApplicationDelegate.window, let scene = GameApplicationDelegate.scene
      else {
        preconditionFailure("the launcher ran without its window")
      }
      // The loading screen stays above the game's window until the game draws.
      window.rootViewController = LoadingViewController()
      window.windowLevel = .alert + 1
      FramePresentation.install(framesPerSecond: screen.framesPerSecond)
      if let controller = VirtualController.install() {
        GamepadOverlay.install(in: scene, controller: controller)
      }
      watchFirstFrames(loading: window)
      // A run-loop timer, not a main-queue block: the game never returns from `main`, and a
      // block would hold the main dispatch queue for the rest of the process.
      Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
        MainActor.assumeIsolated { runGameMain() }
      }
    }

    /// Once the game has drawn 60 frames the touch gamepad appears, the game is told about its
    /// controller two seconds later and the loading screen goes a second after that.
    @MainActor private static func watchFirstFrames(loading window: UIWindow) {
      var drawingSince: Date?
      var announced = false
      Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
        MainActor.assumeIsolated {
          if drawingSince == nil, FramePresentation.drawables.load(ordering: .relaxed) >= 60 {
            drawingSince = .now
            GamepadOverlay.shared?.show()
          }
          guard let drawingSince else { return }
          let elapsed = Date.now.timeIntervalSince(drawingSince)
          if !announced, elapsed >= 2 {
            announced = true
            VirtualController.shared?.announce()
          }
          guard elapsed >= 3 else { return }
          window.isHidden = true
          timer.invalidate()
        }
      }
    }

    @MainActor private static func runGameMain() -> Never {
      let stackSize = 64 << 20
      let guardSize = 64 << 10
      var base: vm_address_t = 0
      guard let gameMain,
        vm_allocate(mach_task_self_, &base, vm_size_t(stackSize + guardSize), VM_FLAGS_ANYWHERE)
          == KERN_SUCCESS,
        vm_protect(mach_task_self_, base, vm_size_t(guardSize), 0, VM_PROT_NONE) == KERN_SUCCESS
      else { preconditionFailure("cannot allocate the game's main-thread stack") }
      RuntimeLog.write("starting the game's main() on a 64 MB stack")
      let top = UnsafeMutableRawPointer(bitPattern: UInt(base) + UInt(stackSize + guardSize))!
      let result = GameRuntimeCallOnStack(
        top,
        { main in
          typealias Arguments = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
          typealias Main =
            @convention(c) (
              Int32, Arguments, Arguments, UnsafeMutablePointer<UnsafePointer<CChar>?>?
            ) -> Int32
          return unsafeBitCast(main, to: Main.self)(
            _NSGetArgc().pointee, _NSGetArgv().pointee, _NSGetEnviron().pointee, nil)
        }, UnsafeMutableRawPointer(mutating: gameMain))
      RuntimeLog.write("game main() returned \(result)")
      exit(result)
    }
  }
#endif
