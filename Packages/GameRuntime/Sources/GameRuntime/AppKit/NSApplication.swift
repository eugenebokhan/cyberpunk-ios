#if os(iOS)
  import GameRuntimeABI
  import UIKit

  /// The game's application object. UIKit owns the process; this object relays launch and
  /// activation to the game's delegate and runs the event poll the game's main loop calls.
  @objc(NSApplication)
  public final class NSApplication: NSResponder {
    static let shared: NSApplication = {
      let application = NSApplication()
      NSApp = Unmanaged.passUnretained(application).toOpaque()
      return application
    }()

    final var windowList: [NSWindow] = []
    final private var storedDelegate: AnyObject?
    final private var active = false
    final private var activationPending = false
    final private var launched = false
    final private var policy = 0
    @MainActor final private var idleTimerDisabled = false

    /// The game's `main` asks for the application first; that is where UIKit takes over.
    @objc public class var sharedApplication: NSApplication {
      if Thread.isMainThread, GameBoot.isCalledFromGameMain() { GameBoot.startUIKit() }
      return shared
    }

    @objc public var delegate: AnyObject? {
      get { storedDelegate }
      set {
        storedDelegate = newValue
        guard newValue != nil, activationPending else { return }
        activationPending = false
        MainThread.async { self.becomeActive(true) }
      }
    }

    @objc public var presentationOptions: UInt = 0
    @objc public var mainMenu: AnyObject?
    @objc public weak var keyWindow: NSWindow?
    @objc public weak var mainWindow: NSWindow?
    @objc public var windows: [NSWindow] { windowList }
    @objc public var orderedWindows: [NSWindow] { windowList }
    @objc public var isActive: Bool { active }
    @objc public var isHidden: Bool { false }
    @objc public var isRunning: Bool { true }
    @objc public var activationPolicy: Int { policy }

    @objc public func setActivationPolicy(_ activationPolicy: Int) -> Bool {
      policy = activationPolicy
      return true
    }

    // iOS decides which app is frontmost and visible.
    @objc public func activateIgnoringOtherApps(_ flag: Bool) {}
    @objc public func hide(_ sender: Any?) {}
    @objc public func unhide(_ sender: Any?) {}
    @objc public func hideOtherApplications(_ sender: Any?) {}
    @objc public func stop(_ sender: Any?) {}

    /// The game registers its controller observers from the launch callbacks.
    @objc public func finishLaunching() {
      guard !launched else { return }
      guard storedDelegate != nil else {
        RuntimeLog.write("finishLaunching before the game set a delegate")
        return
      }
      launched = true
      let launch = Notification(
        name: Notification.Name("NSApplicationDidFinishLaunchingNotification"), object: self)
      tellDelegate("applicationWillFinishLaunching:", launch)
      NotificationCenter.default.post(
        name: Notification.Name("NSApplicationWillFinishLaunchingNotification"), object: self)
      tellDelegate("applicationDidFinishLaunching:", launch)
      NotificationCenter.default.post(launch)
      RuntimeLog.write("finishLaunching: done")
    }

    @objc public func run() {
      MainThread.async {
        if UIApplication.shared.applicationState == .active { self.becomeActive(true) }
      }
      finishLaunching()
      while true { CFRunLoopRun() }
    }

    @objc public func terminate(_ sender: Any?) {
      willTerminate()
      exit(0)
    }

    final func willTerminate() { tellDelegate("applicationWillTerminate:", nil) }

    /// The game's event poll. Events reach the game as they happen through `sendEvent:`; the
    /// poll services the main run loop, a bounded number of sources at a time so input is not
    /// queued behind display callbacks, and holds the game while the app is in the background.
    @objc(nextEventMatchingMask:untilDate:inMode:dequeue:)
    public func nextEvent(
      matching mask: UInt64, until date: Date?, inMode mode: String?, dequeue: Bool
    )
      -> NSEvent?
    {
      let wait = min(max(date?.timeIntervalSinceNow ?? 0, 0), 0.1)
      guard Thread.isMainThread else {
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        return nil
      }
      MainActor.assumeIsolated { poll(wait) }
      return nil
    }

    @MainActor final private func poll(_ wait: TimeInterval) {
      if BackgroundSuspension.isInBackground {
        RuntimeLog.write("background: game held")
        while BackgroundSuspension.isInBackground {
          autoreleasepool {
            _ = CFRunLoopRunInMode(.defaultMode, 0.5, false)
            _dispatch_main_queue_callback_4CF(nil)
          }
        }
        RuntimeLog.write("foreground: game continues")
      }
      if !idleTimerDisabled {
        // A controller does not count as touching the screen.
        idleTimerDisabled = true
        UIApplication.shared.isIdleTimerDisabled = true
      }
      CDPRSession.restoreIfNeeded()
      var result = CFRunLoopRunInMode(.defaultMode, wait, true)
      var handled = 0
      while result == .handledSource, handled < 64 {
        result = CFRunLoopRunInMode(.defaultMode, 0, true)
        handled += 1
      }
    }

    @objc(postEvent:atStart:) public func post(_ event: NSEvent, atStart: Bool) { dispatch(event) }

    @objc public func sendEvent(_ event: NSEvent) {
      guard let selector = event.responderSelector else { return }
      let window = keyWindow ?? windowList.first
      var target: AnyObject? = window?.firstResponder ?? window?.contentView
      if !event.isKeyboardEvent, var view = window?.contentView {
        // Mouse-type events go to the deepest visible view under the event that handles them.
        var handler: NSView? = view.responds(to: selector) ? view : nil
        while let next = view.subviews.reversed().first(where: {
          !$0.isHidden && $0.frame.contains(event.locationInWindow)
        }) {
          view = next
          if view.responds(to: selector) { handler = view }
        }
        if let handler { target = handler }
      }
      guard let target, target.responds(to: selector) else { return }
      _ = target.perform(selector, with: event)
    }

    /// Runs the game's local event monitors, then delivers the event.
    final func dispatch(_ event: NSEvent) {
      guard let event = NSEvent.monitored(event) else { return }
      sendEvent(event)
    }

    @MainActor final func becomeActive(_ isActive: Bool) {
      if isActive, storedDelegate == nil {
        activationPending = true
        return
      }
      if !isActive { activationPending = false }
      guard isActive != active else { return }
      active = isActive
      RuntimeLog.write("game told: app \(isActive ? "active" : "inactive")")
      let before = Notification(
        name: Notification.Name(
          isActive
            ? "NSApplicationWillBecomeActiveNotification"
            : NSApplicationWillResignActiveNotification as String),
        object: self)
      let after = Notification(
        name: Notification.Name(
          (isActive
            ? NSApplicationDidBecomeActiveNotification : NSApplicationDidResignActiveNotification)
            as String), object: self)
      NotificationCenter.default.post(before)
      tellDelegate(
        isActive ? "applicationWillBecomeActive:" : "applicationWillResignActive:", before)
      for window in windowList {
        if !isActive {
          window.resignKey()
        } else if window === keyWindow || windowList.count == 1 {
          window.becomeKey()
        }
      }
      NotificationCenter.default.post(after)
      tellDelegate(isActive ? "applicationDidBecomeActive:" : "applicationDidResignActive:", after)
    }

    final private func tellDelegate(_ selector: String, _ notification: Notification?) {
      guard let delegate = storedDelegate, delegate.responds(to: Selector((selector))) else {
        return
      }
      _ = delegate.perform(Selector((selector)), with: notification)
    }
  }
#endif
