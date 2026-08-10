#if os(iOS)
  import Synchronization
  import UIKit

  /// The app screen as UIKit reports it, readable from the game's threads.
  struct ScreenMetrics: Sendable {
    /// Size in points, landscape.
    var size: CGSize
    var nativeScale: CGFloat
    var framesPerSecond: Int

    private static let measured = Mutex<ScreenMetrics?>(nil)

    static var current: ScreenMetrics { measured.withLock { $0 } ?? refresh() }

    /// AppKit points per UIKit point. The engine assumes a 2x backing scale, so the chosen
    /// render mode is presented as the AppKit size of the screen.
    static var appKitScale: CGFloat { DisplayMode.selected.scale }

    static var appKitSize: CGSize {
      let size = current.size
      return CGSize(width: size.width * appKitScale, height: size.height * appKitScale)
    }

    @discardableResult
    static func refresh() -> ScreenMetrics {
      let metrics = MainThread.sync {
        let screen = GameApplicationDelegate.scene?.screen ?? UIScreen.main
        let size = screen.bounds.size
        return ScreenMetrics(
          size: CGSize(width: max(size.width, size.height), height: min(size.width, size.height)),
          nativeScale: screen.nativeScale,
          framesPerSecond: screen.maximumFramesPerSecond)
      }
      measured.withLock { $0 = metrics }
      return metrics
    }
  }
#endif
