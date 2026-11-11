#if os(iOS)
  import QuartzCore
  import UIKit

  enum FramePresentation {
    @MainActor private static var installed = false

    @MainActor static func install() {
      guard !installed else { return }
      installed = true
      RefreshRateRequest().start()
    }
  }

  @MainActor private final class RefreshRateRequest: NSObject {
    private lazy var link = CADisplayLink(target: self, selector: #selector(step))

    func start() {
      let center = NotificationCenter.default
      center.addObserver(
        self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification,
        object: nil)
      center.addObserver(
        self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification,
        object: nil)
      step(link)
      link.add(to: .main, forMode: .common)
    }

    @objc private func step(_ link: CADisplayLink) {
      let maximum = Float(ScreenMetrics.screen.maximumFramesPerSecond)
      if link.preferredFrameRateRange.preferred != maximum {
        link.preferredFrameRateRange = CAFrameRateRange(
          minimum: maximum, maximum: maximum, preferred: maximum)
      }
      link.isPaused = BackgroundSuspension.isInBackground
    }

    @objc private func background() { link.isPaused = true }
    @objc private func foreground() { step(link) }
  }
#endif
