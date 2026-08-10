#if os(iOS)
  import UIKit

  /// The phone screen as an AppKit screen: the chosen render mode is its size in AppKit points,
  /// at the 2x backing scale the engine expects.
  @objc(NSScreen)
  public final class NSScreen: NSObject {
    @objc(mainScreen) public static let main = NSScreen()
    @objc public class var screens: [NSScreen] { [main] }

    @objc public var frame: CGRect { CGRect(origin: .zero, size: ScreenMetrics.appKitSize) }
    @objc public var visibleFrame: CGRect { frame }
    @objc public var backingScaleFactor: CGFloat { 2 }
    @objc public var maximumFramesPerSecond: Int { ScreenMetrics.current.framesPerSecond }

    /// UIKit reports the screen's highest rate only, so the screen is a fixed-rate display; AppKit
    /// reports equal intervals for those.
    @objc public var minimumRefreshInterval: TimeInterval { 1 / Double(maximumFramesPerSecond) }
    @objc public var maximumRefreshInterval: TimeInterval { minimumRefreshInterval }

    @objc public var maximumExtendedDynamicRangeColorComponentValue: CGFloat {
      MainThread.sync { max(1, GameApplicationDelegate.scene?.screen.currentEDRHeadroom ?? 1) }
    }

    @objc public var maximumPotentialExtendedDynamicRangeColorComponentValue: CGFloat {
      MainThread.sync { max(1, GameApplicationDelegate.scene?.screen.potentialEDRHeadroom ?? 1) }
    }

    @objc public var localizedName: String { "Built-in Display" }

    @objc public var deviceDescription: [String: Any] {
      [
        "NSScreenNumber": 1 as UInt32, "NSDeviceSize": NSValue(cgSize: frame.size),
        "NSDeviceResolution": NSValue(
          cgSize: CGSize(width: 72 * backingScaleFactor, height: 72 * backingScaleFactor)),
      ]
    }
  }
#endif
