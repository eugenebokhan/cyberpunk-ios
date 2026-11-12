import Foundation

enum AppKitCoordinates {
  static func uiPoint(
    _ point: CGPoint, height: CGFloat, flipped: Bool, scale: CGFloat
  ) -> CGPoint {
    CGPoint(x: point.x / scale, y: (flipped ? point.y : height - point.y) / scale)
  }

  static func appKitPoint(
    _ point: CGPoint, height: CGFloat, flipped: Bool, scale: CGFloat
  ) -> CGPoint {
    CGPoint(x: point.x * scale, y: flipped ? point.y * scale : height - point.y * scale)
  }

  static func uiFrame(
    _ frame: CGRect, parentHeight: CGFloat, parentFlipped: Bool, scale: CGFloat
  ) -> CGRect {
    CGRect(
      x: frame.minX / scale,
      y: (parentFlipped ? frame.minY : parentHeight - frame.maxY) / scale,
      width: frame.width / scale, height: frame.height / scale)
  }

  static func appKitRect(
    _ rect: CGRect, height: CGFloat, flipped: Bool, scale: CGFloat
  ) -> CGRect {
    CGRect(
      x: rect.minX * scale, y: flipped ? rect.minY * scale : height - rect.maxY * scale,
      width: rect.width * scale, height: rect.height * scale)
  }
}

#if os(iOS)
  import QuartzCore
  import UIKit

  @objc(NSView)
  public class NSView: NSResponder {
    final private(set) var host: GameHostView!
    final private var rectangle: CGRect
    final private var suppliedLayer: CALayer?
    final private var childViews: [NSView] = []
    final private var areas: [NSTrackingArea] = []
    final private var cursorRects: [(rect: CGRect, cursor: NSCursor?)] = []
    final private var resizeMask: UInt = 0
    final private var hidden = false
    final private var layerRequested = false
    final private weak var parentView: NSView?
    final private weak var attachedWindow: NSWindow?

    @objc dynamic public init(frame: CGRect) {
      rectangle = frame
      super.init()
      MainThread.sync {
        let scale = ScreenMetrics.appKitScale
        host = GameHostView.make(
          for: self,
          frame: CGRect(
            x: frame.minX / scale, y: frame.minY / scale,
            width: frame.width / scale, height: frame.height / scale))
      }
    }

    @objc public override convenience init() {
      self.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @objc dynamic public var frame: CGRect {
      get { MainThread.sync { rectangle } }
      set {
        MainThread.sync {
          rectangle = newValue
          placeHost()
        }
      }
    }

    @objc dynamic public var bounds: CGRect {
      MainThread.sync { CGRect(origin: .zero, size: rectangle.size) }
    }

    @objc dynamic public func setFrameSize(_ size: CGSize) {
      MainThread.sync { frame = CGRect(origin: rectangle.origin, size: size) }
    }

    @objc dynamic public func setFrameOrigin(_ origin: CGPoint) {
      MainThread.sync { frame = CGRect(origin: origin, size: rectangle.size) }
    }

    @objc dynamic public var window: NSWindow? { MainThread.sync { attachedWindow } }
    @objc dynamic public var superview: NSView? { MainThread.sync { parentView } }
    @objc dynamic public var subviews: [NSView] { MainThread.sync { childViews } }

    @objc dynamic public func addSubview(_ view: NSView) {
      MainThread.sync {
        precondition(view !== self, "a view cannot contain itself")
        var ancestor: NSView? = self
        while let current = ancestor {
          precondition(current !== view, "a view hierarchy cannot contain a cycle")
          ancestor = current.parentView
        }
        if view.parentView === self {
          childViews.removeAll { $0 === view }
        } else {
          view.removeFromSuperview()
          view.parentView = self
          view.nextResponder = self
        }
        childViews.append(view)
        host.addSubview(view.host)
        view.applyAutoresizingMask()
        view.placeHost()
        view.attach(to: attachedWindow)
      }
    }

    @objc dynamic public func removeFromSuperview() {
      MainThread.sync {
        if let attachedWindow, attachedWindow.contentView === self {
          attachedWindow.contentView = nil
          return
        }
        attachedWindow?.detachFirstResponder(in: self)
        parentView?.childViews.removeAll { $0 === self }
        parentView = nil
        nextResponder = nil
        cursorRects.removeAll()
        host.removeFromSuperview()
        attach(to: nil)
      }
    }

    @objc dynamic public var wantsLayer: Bool {
      get { MainThread.sync { layerRequested } }
      set { MainThread.sync { layerRequested = newValue } }
    }

    @objc dynamic public var layer: CALayer? {
      get { MainThread.sync { suppliedLayer ?? host.layer } }
      set {
        MainThread.sync {
          guard suppliedLayer !== newValue else { return }
          suppliedLayer?.removeFromSuperlayer()
          suppliedLayer = newValue === host.layer ? nil : newValue
          guard let suppliedLayer else { return }
          suppliedLayer.contentsScale =
            host.window?.screen.nativeScale ?? ScreenMetrics.current.nativeScale
          suppliedLayer.frame = host.bounds
          host.layer.addSublayer(suppliedLayer)
        }
      }
    }

    @objc dynamic public var isHidden: Bool {
      @objc(isHidden) get { MainThread.sync { hidden } }
      @objc(setHidden:) set {
        MainThread.sync {
          hidden = newValue
          host.isHidden = newValue
        }
      }
    }

    @objc dynamic public var autoresizingMask: UInt {
      get { MainThread.sync { resizeMask } }
      set {
        MainThread.sync {
          resizeMask = newValue
          applyAutoresizingMask()
        }
      }
    }

    @objc(setNeedsDisplay:) dynamic public func setNeedsDisplay(_ needsDisplay: Bool) {
      if needsDisplay { MainThread.async { self.host.setNeedsDisplay() } }
    }

    // These base hooks are overridden by the game's Objective-C view subclasses.
    @objc(drawRect:) dynamic public func draw(_ dirtyRect: CGRect) {}
    @objc dynamic public func viewDidChangeBackingProperties() {}
    @objc dynamic public func viewDidMoveToWindow() {}
    @objc dynamic public func updateTrackingAreas() {}
    @objc dynamic public func resetCursorRects() {}

    @objc dynamic public var trackingAreas: [NSTrackingArea] { MainThread.sync { areas } }
    @objc dynamic public func addTrackingArea(_ area: NSTrackingArea) {
      MainThread.sync { if !areas.contains(where: { $0 === area }) { areas.append(area) } }
    }
    @objc dynamic public func removeTrackingArea(_ area: NSTrackingArea) {
      MainThread.sync { areas.removeAll { $0 === area } }
    }
    @objc dynamic public func discardCursorRects() { MainThread.sync { cursorRects.removeAll() } }
    @objc(addCursorRect:cursor:) dynamic public func addCursorRect(
      _ rect: CGRect, cursor: NSCursor?
    ) {
      MainThread.sync { cursorRects.append((rect, cursor)) }
    }

    // A view's drawing context is supplied only during UIKit's draw callback.
    @objc dynamic public func lockFocus() {}
    @objc dynamic public func unlockFocus() {}

    @objc(convertPoint:fromView:) dynamic public func convert(_ point: CGPoint, from view: NSView?)
      -> CGPoint
    {
      MainThread.sync {
        guard let attached = window, view == nil || view?.window === attached else {
          preconditionFailure("coordinate conversion requires views in the same window")
        }
        let scale = ScreenMetrics.appKitScale
        let sourceHeight = view?.bounds.height ?? attached.frame.height
        let source = AppKitCoordinates.uiPoint(
          point, height: sourceHeight, flipped: view?.isFlipped ?? false, scale: scale)
        return AppKitCoordinates.appKitPoint(
          host.convert(source, from: view?.host), height: bounds.height, flipped: isFlipped,
          scale: scale)
      }
    }

    @objc(convertPoint:toView:) dynamic public func convert(_ point: CGPoint, to view: NSView?)
      -> CGPoint
    {
      MainThread.sync {
        guard let attached = window, view == nil || view?.window === attached else {
          preconditionFailure("coordinate conversion requires views in the same window")
        }
        let scale = ScreenMetrics.appKitScale
        let source = AppKitCoordinates.uiPoint(
          point, height: bounds.height, flipped: isFlipped, scale: scale)
        let targetHeight = view?.bounds.height ?? attached.frame.height
        return AppKitCoordinates.appKitPoint(
          host.convert(source, to: view?.host), height: targetHeight,
          flipped: view?.isFlipped ?? false, scale: scale)
      }
    }

    @objc dynamic public func convertRectToBacking(_ rect: CGRect) -> CGRect {
      let scale = window?.backingScaleFactor ?? NSScreen.main.backingScaleFactor
      return rect.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    @objc dynamic public func convertRectFromBacking(_ rect: CGRect) -> CGRect {
      let scale = window?.backingScaleFactor ?? NSScreen.main.backingScaleFactor
      return rect.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }

    @objc dynamic public var canBecomeKeyView: Bool { true }
    @objc dynamic public var mouseDownCanMoveWindow: Bool { false }
    @objc dynamic public var isFlipped: Bool { false }

    @MainActor final func containsResponder(_ responder: NSResponder?) -> Bool {
      var candidate = responder as? NSView
      while let view = candidate {
        if view === self { return true }
        candidate = view.parentView
      }
      return false
    }

    @MainActor final func attach(to window: NSWindow?) {
      guard attachedWindow !== window else { return }
      attachedWindow = window
      for child in childViews { child.attach(to: window) }
      viewDidMoveToWindow()
    }

    @MainActor final func hitView(at windowPoint: CGPoint) -> NSView? {
      guard !hidden, bounds.contains(convert(windowPoint, from: nil)) else { return nil }
      for child in childViews.reversed() {
        if let hit = child.hitView(at: windowPoint) { return hit }
      }
      return self
    }

    @MainActor final private func applyAutoresizingMask() {
      let vertical =
        parentView?.isFlipped == true
        ? resizeMask & 0x38
        : ((resizeMask & 8) << 2) | (resizeMask & 16) | ((resizeMask & 32) >> 2)
      host.autoresizingMask = UIView.AutoresizingMask(rawValue: (resizeMask & 7) | vertical)
    }

    @MainActor final private func placeHost() {
      guard let parentView else { return }
      host.frame = AppKitCoordinates.uiFrame(
        rectangle, parentHeight: parentView.bounds.height, parentFlipped: parentView.isFlipped,
        scale: ScreenMetrics.appKitScale)
    }

    @MainActor final func layoutFromHost() {
      let size = CGSize(
        width: host.bounds.width * ScreenMetrics.appKitScale,
        height: host.bounds.height * ScreenMetrics.appKitScale)
      if let suppliedLayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        suppliedLayer.frame = host.bounds
        CATransaction.commit()
      }
      guard rectangle.size != size else { return }
      rectangle.size = size
      viewDidChangeBackingProperties()
      if let window = attachedWindow, window.contentView === self { window.contentDidResize() }
    }
  }
#endif
