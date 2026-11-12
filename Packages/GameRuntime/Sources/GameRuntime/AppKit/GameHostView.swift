#if os(iOS)
  import UIKit

  class GameHostView: UIView {
    weak var owner: NSView?

    @MainActor static func make(for owner: NSView, frame: CGRect) -> GameHostView {
      let selector = #selector(NSView.draw(_:))
      let hasDrawing =
        class_getMethodImplementation(object_getClass(owner), selector)
        != class_getMethodImplementation(NSView.self, selector)
      let view = hasDrawing ? GameDrawingHostView(frame: frame) : GameHostView(frame: frame)
      view.owner = owner
      view.backgroundColor = .clear
      return view
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      owner?.layoutFromHost()
    }
  }

  final class GameDrawingHostView: GameHostView {
    override func draw(_ rect: CGRect) {
      guard let owner, let context = UIGraphicsGetCurrentContext() else { return }
      let scale = ScreenMetrics.appKitScale
      context.saveGState()
      defer { context.restoreGState() }
      if !owner.isFlipped {
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1 / scale, y: -1 / scale)
      } else {
        context.scaleBy(x: 1 / scale, y: 1 / scale)
      }
      owner.draw(
        AppKitCoordinates.appKitRect(
          rect, height: owner.bounds.height, flipped: owner.isFlipped, scale: scale))
    }
  }
#endif
