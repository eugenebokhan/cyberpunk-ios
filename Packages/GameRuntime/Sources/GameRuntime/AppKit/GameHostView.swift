#if os(iOS)
  import UIKit

  /// The UIKit view behind an `NSView`: it carries the view's layer and subviews and reports
  /// layout back to its owner.
  class GameHostView: UIView {
    weak var owner: NSView?

    @MainActor static func make(for owner: NSView, frame: CGRect) -> GameHostView {
      // Only views that draw get a backing store; the game's Metal view does not draw.
      let drawRect = #selector(NSView.draw(_:))
      let draws =
        class_getMethodImplementation(object_getClass(owner), drawRect)
        != class_getMethodImplementation(NSView.self, drawRect)
      let host = draws ? GameDrawingHostView(frame: frame) : GameHostView(frame: frame)
      host.owner = owner
      host.backgroundColor = .clear
      return host
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      owner?.layoutFromHost()
    }
  }

  /// Draws its owner's `drawRect:` in AppKit coordinates: bottom-left origin, AppKit points.
  final class GameDrawingHostView: GameHostView {
    override func draw(_ rect: CGRect) {
      guard let owner, let context = UIGraphicsGetCurrentContext() else { return }
      let scale = ScreenMetrics.appKitScale
      context.saveGState()
      context.translateBy(x: 0, y: bounds.height)
      context.scaleBy(x: 1 / scale, y: -1 / scale)
      owner.draw(
        CGRect(
          x: rect.minX * scale, y: (bounds.height - rect.maxY) * scale, width: rect.width * scale,
          height: rect.height * scale))
      context.restoreGState()
    }
  }
#endif
