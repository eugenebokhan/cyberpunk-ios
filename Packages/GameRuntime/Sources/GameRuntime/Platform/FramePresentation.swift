#if os(iOS)
  import Foundation
  import Metal
  import QuartzCore
  import Synchronization

  /// Presentation of the game's Metal frames on an iPhone display.
  ///
  /// The engine paces itself as on a Mac: plainly when uncapped, or with a minimum frame duration.
  /// iOS shows more than 60 frames per second only while the app asks for a faster refresh rate,
  /// so the runtime requests one whenever the game's cadence does not fit 60 Hz, gives uncapped
  /// presents the display's shortest duration, and leaves 2 ms of slack on minimum durations so a
  /// frame finished on time is not held for a whole extra refresh. Frame generation keeps its own
  /// cadence through the same path.
  enum FramePresentation {
    /// Drawables the game has acquired; the start-up sequence waits for the first frames.
    static let drawables = Atomic(0)
    /// The minimum duration the game last presented with: 0 uncapped, -1 before it presents.
    private static let gameMinimumDuration = Atomic((-1.0).bitPattern)
    private static let presentedByCommandBuffer = UnsafeRawPointer(
      UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    private static func margin(_ duration: CFTimeInterval) -> CFTimeInterval {
      duration > 0.004 ? duration - 0.002 : duration
    }

    @MainActor static func install(framesPerSecond: Int) {
      countDrawables()
      let uncapped = framesPerSecond > 60 ? margin(1 / Double(framesPerSecond)) : 0
      guard let device = MTLCreateSystemDefaultDevice(),
        let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
        let commandBufferClass = object_getClass(commandBuffer),
        let drawableClass = NSClassFromString("CAMetalDrawable")
      else {
        RuntimeLog.write("frame presentation hooks unavailable")
        return
      }
      hookCommandBuffer(commandBufferClass, uncapped: uncapped)
      hookDrawable(drawableClass, uncapped: uncapped)
      if framesPerSecond > 60 { RefreshRateRequest.start(framesPerSecond: framesPerSecond) }
    }

    static var gameCadence: CFTimeInterval {
      Double(bitPattern: gameMinimumDuration.load(ordering: .relaxed))
    }

    private static func recordCadence(_ duration: CFTimeInterval) {
      gameMinimumDuration.store(duration.bitPattern, ordering: .relaxed)
    }

    private static func countDrawables() {
      let selector = #selector(CAMetalLayer.nextDrawable)
      ObjectiveCRuntime.replace(CAMetalLayer.self, selector) { original in
        typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let next = unsafeBitCast(original, to: Function.self)
        let block: @convention(block) (AnyObject) -> Unmanaged<AnyObject>? = { layer in
          drawables.add(1, ordering: .relaxed)
          return next(layer, selector)
        }
        return block
      }
    }

    private static func hookCommandBuffer(_ cls: AnyClass, uncapped: CFTimeInterval) {
      typealias PresentAfter =
        @convention(c) (AnyObject, Selector, AnyObject?, CFTimeInterval) -> Void
      let presentAfter = #selector(MTLCommandBuffer.present(_:afterMinimumDuration:))
      guard let method = class_getInstanceMethod(cls, presentAfter) else { return }
      let originalPresentAfter = unsafeBitCast(
        method_getImplementation(method), to: PresentAfter.self)
      ObjectiveCRuntime.replace(cls, presentAfter) { _ in
        let block: @convention(block) (AnyObject, AnyObject?, CFTimeInterval) -> Void = {
          buffer, drawable, duration in
          recordCadence(duration)
          markPresented(drawable)
          originalPresentAfter(buffer, presentAfter, drawable, margin(duration))
        }
        return block
      }
      let present = #selector(
        MTLCommandBuffer.present(_:) as (MTLCommandBuffer) -> (MTLDrawable) -> Void)
      ObjectiveCRuntime.replace(cls, present) { original in
        let originalPresent = unsafeBitCast(
          original, to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Void).self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { buffer, drawable in
          recordCadence(0)
          markPresented(drawable)
          if uncapped > 0 {
            originalPresentAfter(buffer, presentAfter, drawable, uncapped)
          } else {
            originalPresent(buffer, present, drawable)
          }
        }
        return block
      }
    }

    /// Drawables a command buffer presents reach these too; those keep the buffer's duration.
    private static func hookDrawable(_ cls: AnyClass, uncapped: CFTimeInterval) {
      typealias PresentAfter = @convention(c) (AnyObject, Selector, CFTimeInterval) -> Void
      let presentAfter = #selector(MTLDrawable.present(afterMinimumDuration:))
      guard let method = class_getInstanceMethod(cls, presentAfter) else { return }
      let originalPresentAfter = unsafeBitCast(
        method_getImplementation(method), to: PresentAfter.self)
      ObjectiveCRuntime.replace(cls, presentAfter) { _ in
        let block: @convention(block) (AnyObject, CFTimeInterval) -> Void = { drawable, duration in
          if isPresented(drawable) { return originalPresentAfter(drawable, presentAfter, duration) }
          recordCadence(duration)
          originalPresentAfter(drawable, presentAfter, margin(duration))
        }
        return block
      }
      let present = #selector(MTLDrawable.present as (MTLDrawable) -> () -> Void)
      ObjectiveCRuntime.replace(cls, present) { original in
        let originalPresent = unsafeBitCast(
          original, to: (@convention(c) (AnyObject, Selector) -> Void).self)
        let block: @convention(block) (AnyObject) -> Void = { drawable in
          if isPresented(drawable) { return originalPresent(drawable, present) }
          recordCadence(0)
          if uncapped > 0 {
            originalPresentAfter(drawable, presentAfter, uncapped)
          } else {
            originalPresent(drawable, present)
          }
        }
        return block
      }
    }

    private static func markPresented(_ drawable: AnyObject?) {
      guard let drawable else { return }
      objc_setAssociatedObject(
        drawable, presentedByCommandBuffer, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func isPresented(_ drawable: AnyObject) -> Bool {
      objc_getAssociatedObject(drawable, presentedByCommandBuffer) != nil
    }
  }

  /// Asks Core Animation for the display's fastest refresh while the game's cadence does not fit
  /// 60 Hz (uncapped, 40 FPS, 120 FPS); capped 60, 30 and 20 FPS run at the system default rate.
  private final class RefreshRateRequest: NSObject {
    @objc func step(_ link: CADisplayLink) {}

    static func start(framesPerSecond: Int) {
      let thread = Thread {
        let request = RefreshRateRequest()
        let link = CADisplayLink(target: request, selector: #selector(step))
        let maximum = Float(framesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(
          minimum: 80, maximum: maximum, preferred: maximum)
        link.isPaused = true
        link.add(to: .current, forMode: .common)
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
          let cadence = FramePresentation.gameCadence
          let rate = cadence > 0 ? (1 / cadence).rounded() : 0
          let fitsSixty = rate > 0 && rate <= 60 && abs(60 / rate - (60 / rate).rounded()) < 0.05
          let wanted = cadence >= 0 && !fitsSixty && !BackgroundSuspension.isInBackground
          guard link.isPaused == wanted else { return }
          link.isPaused = !wanted
          RuntimeLog.write(
            "screen: \(wanted ? "requesting \(framesPerSecond) Hz" : "system refresh rate")")
        }
        RunLoop.current.add(timer, forMode: .common)
        RunLoop.current.run()
      }
      thread.name = "Cyberpunk.refresh"
      thread.qualityOfService = .utility
      thread.start()
    }
  }
#endif
