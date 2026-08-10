#if os(iOS)
  import QuartzCore
  import UIKit

  /// An AppKit view backed by a UIKit host view. Frames are in AppKit points: UIKit points scaled
  /// by the render mode.
  @objc(NSView)
  public class NSView: NSResponder {
    final private(set) var host: GameHostView!
    final private var hostLayer: CALayer!
    final private var storedFrame: CGRect
    final private var storedLayer: CALayer?
    final private var children: [NSView] = []
    final private var areas: [NSTrackingArea] = []
    final private var cursorRects: [(rect: CGRect, cursor: NSCursor?)] = []
    final private var storedMask: UInt = 0
    final private var storedHidden = false
    final private var storedWantsLayer = false
    final private weak var parent: NSView?
    final weak var hostingWindow: NSWindow?

    @objc dynamic public init(frame: CGRect) {
      storedFrame = frame
      super.init()
      let scale = ScreenMetrics.appKitScale
      let uiFrame = CGRect(
        x: frame.minX / scale, y: frame.minY / scale, width: frame.width / scale,
        height: frame.height / scale)
      host = MainThread.sync { GameHostView.make(for: self, frame: uiFrame) }
      hostLayer = MainThread.sync { host.layer }
    }

    @objc public override convenience init() {
      self.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @objc dynamic public var frame: CGRect {
      get { storedFrame }
      set {
        storedFrame = newValue
        MainThread.sync { placeHost() }
      }
    }

    @objc dynamic public var bounds: CGRect { CGRect(origin: .zero, size: storedFrame.size) }

    @objc dynamic public func setFrameSize(_ size: CGSize) {
      frame = CGRect(origin: storedFrame.origin, size: size)
    }

    @objc dynamic public func setFrameOrigin(_ origin: CGPoint) {
      frame = CGRect(origin: origin, size: storedFrame.size)
    }

    @objc dynamic public var window: NSWindow? { hostingWindow ?? parent?.window }
    @objc dynamic public var superview: NSView? { parent }
    @objc dynamic public var subviews: [NSView] { children }

    @objc dynamic public func addSubview(_ view: NSView) {
      children.append(view)
      view.parent = self
      MainThread.sync {
        host.addSubview(view.host)
        view.placeHost()
      }
    }

    @objc dynamic public func removeFromSuperview() {
      parent?.children.removeAll { $0 === self }
      parent = nil
      MainThread.sync { host.removeFromSuperview() }
    }

    @objc dynamic public var wantsLayer: Bool {
      get { storedWantsLayer }
      set { storedWantsLayer = newValue }
    }

    /// The game hands its CAMetalLayer to its content view; it fills the host view.
    @objc dynamic public var layer: CALayer? {
      get { storedLayer ?? hostLayer }
      set {
        storedLayer = newValue
        guard let newValue else { return }
        MainThread.sync {
          newValue.contentsScale =
            host.window?.screen.nativeScale ?? ScreenMetrics.current.nativeScale
          newValue.frame = host.bounds
          host.layer.addSublayer(newValue)
        }
      }
    }

    @objc dynamic public var isHidden: Bool {
      @objc(isHidden) get { storedHidden }
      @objc(setHidden:) set {
        storedHidden = newValue
        MainThread.sync { host.isHidden = newValue }
      }
    }

    /// AppKit autoresizing; its y margins are mirrored in UIKit's top-left coordinates.
    @objc dynamic public var autoresizingMask: UInt {
      get { storedMask }
      set {
        storedMask = newValue
        let mask = (newValue & 7) | ((newValue & 8) << 2) | (newValue & 16) | ((newValue & 32) >> 2)
        MainThread.sync { host.autoresizingMask = UIView.AutoresizingMask(rawValue: mask) }
      }
    }

    @objc(setNeedsDisplay:) dynamic public func setNeedsDisplay(_ needsDisplay: Bool) {
      guard needsDisplay else { return }
      MainThread.async { [host] in host?.setNeedsDisplay() }
    }

    @objc(drawRect:) dynamic public func draw(_ dirtyRect: CGRect) {}
    @objc dynamic public func viewDidChangeBackingProperties() {}
    @objc dynamic public func viewDidMoveToWindow() {}
    @objc dynamic public func updateTrackingAreas() {}

    @objc dynamic public var trackingAreas: [NSTrackingArea] { areas }
    @objc dynamic public func addTrackingArea(_ area: NSTrackingArea) { areas.append(area) }
    @objc dynamic public func removeTrackingArea(_ area: NSTrackingArea) {
      areas.removeAll { $0 === area }
    }

    @objc dynamic public func resetCursorRects() {}
    @objc dynamic public func discardCursorRects() { cursorRects.removeAll() }
    @objc(addCursorRect:cursor:) dynamic public func addCursorRect(
      _ rect: CGRect, cursor: NSCursor?
    ) {
      cursorRects.append((rect, cursor))
    }

    /// Immediate-mode drawing outside `drawRect:` has no UIKit equivalent; views draw when
    /// UIKit asks them to.
    @objc dynamic public func lockFocus() {}
    @objc dynamic public func unlockFocus() {}

    @objc(convertPoint:fromView:) dynamic public func convert(_ point: CGPoint, from view: NSView?)
      -> CGPoint
    {
      let from = view?.originInWindow ?? .zero
      let to = originInWindow
      return CGPoint(x: point.x + from.x - to.x, y: point.y + from.y - to.y)
    }

    @objc(convertPoint:toView:) dynamic public func convert(_ point: CGPoint, to view: NSView?)
      -> CGPoint
    {
      let from = originInWindow
      let to = view?.originInWindow ?? .zero
      return CGPoint(x: point.x + from.x - to.x, y: point.y + from.y - to.y)
    }

    @objc dynamic public func convertRectToBacking(_ rect: CGRect) -> CGRect {
      rect.applying(CGAffineTransform(scaleX: 2, y: 2))
    }

    @objc dynamic public func convertRectFromBacking(_ rect: CGRect) -> CGRect {
      rect.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
    }

    @objc dynamic public var canBecomeKeyView: Bool { true }
    @objc dynamic public var mouseDownCanMoveWindow: Bool { false }
    @objc dynamic public var isFlipped: Bool { false }

    final private var originInWindow: CGPoint {
      var origin = storedFrame.origin
      var ancestor = parent
      while let view = ancestor {
        origin.x += view.storedFrame.minX
        origin.y += view.storedFrame.minY
        ancestor = view.parent
      }
      return origin
    }

    /// Positions a subview's host in its superview's host. Subview origins are placed from the
    /// top, as the game's text and scroll views (flipped in AppKit) expect.
    @MainActor final private func placeHost() {
      guard parent != nil else { return }
      let scale = ScreenMetrics.appKitScale
      host.frame = CGRect(
        x: storedFrame.minX / scale, y: storedFrame.minY / scale, width: storedFrame.width / scale,
        height: storedFrame.height / scale)
    }

    /// The host view was laid out: the AppKit size follows it and the game is told.
    @MainActor final func layoutFromHost() {
      let bounds = host.bounds
      let scale = ScreenMetrics.appKitScale
      let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      if let storedLayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        storedLayer.frame = bounds
        CATransaction.commit()
      }
      guard size != storedFrame.size else { return }
      storedFrame.size = size
      viewDidChangeBackingProperties()
      if let window = hostingWindow, window.contentView === self { window.contentDidResize() }
    }
  }
#endif
