#if os(iOS)
  import GameRuntimeABI
  import UIKit

  @objc(NSWindow)
  public class NSWindow: NSResponder {
    private static let fullScreenStyle: UInt = 1 << 14

    final private(set) var uiWindow: UIWindow!
    final private var content: NSView?
    final private weak var responder: NSResponder?
    final private var style: UInt
    final private var minimumSize = CGSize.zero
    final private var mouseMovementAccepted = false
    final private var caption: String?
    final private var closing = false
    final private var visible = false
    final private var key = false
    final private var main = false
    final private weak var observer: AnyObject?
    final private weak var controller: AnyObject?

    @objc(initWithContentRect:styleMask:backing:defer:screen:)
    dynamic public init(
      contentRect: CGRect, styleMask: UInt, backing: UInt, defer deferCreation: Bool,
      screen: NSScreen?
    ) {
      style = styleMask
      super.init()
      MainThread.sync {
        guard let scene = GameApplicationDelegate.scene else {
          preconditionFailure("a game window requires a connected UIKit scene")
        }
        uiWindow = UIWindow(windowScene: scene)
        uiWindow.rootViewController = GameRootViewController()
        uiWindow.backgroundColor = .black
        nextResponder = NSApplication.shared
        register()
      }
    }

    @objc(initWithContentRect:styleMask:backing:defer:)
    public convenience init(
      contentRect: CGRect, styleMask: UInt, backing: UInt, defer deferCreation: Bool
    ) {
      self.init(
        contentRect: contentRect, styleMask: styleMask, backing: backing,
        defer: deferCreation, screen: nil)
    }

    @objc public override convenience init() {
      self.init(contentRect: .zero, styleMask: 1, backing: 2, defer: false)
    }

    @objc dynamic public var contentView: NSView? {
      get { MainThread.sync { content } }
      set {
        MainThread.sync {
          guard content !== newValue else { return }
          let previous = content
          content = nil
          if let previous { detachFirstResponder(in: previous) }
          previous?.host.removeFromSuperview()
          previous?.nextResponder = nil
          previous?.attach(to: nil)
          guard let view = newValue else { return }
          view.removeFromSuperview()
          guard let root = uiWindow.rootViewController?.view else {
            preconditionFailure("a game window has no root view")
          }
          content = view
          view.nextResponder = self
          view.host.frame = root.bounds
          view.host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          view.host.backgroundColor = .black
          root.addSubview(view.host)
          view.attach(to: self)
          view.layoutFromHost()
        }
      }
    }

    @objc dynamic public var delegate: AnyObject? {
      get { MainThread.sync { observer } }
      set { MainThread.sync { observer = newValue } }
    }

    @objc dynamic public var windowController: AnyObject? {
      get { MainThread.sync { controller } }
      set {
        MainThread.sync {
          controller = newValue
          nextResponder = (newValue as? NSResponder) ?? NSApplication.shared
        }
      }
    }

    @objc dynamic public var styleMask: UInt {
      get { MainThread.sync { style } }
      set { MainThread.sync { style = newValue } }
    }
    @objc dynamic public var title: String? {
      get { MainThread.sync { caption } }
      set { MainThread.sync { caption = newValue } }
    }
    @objc dynamic public var minSize: CGSize {
      get { MainThread.sync { minimumSize } }
      set { MainThread.sync { minimumSize = newValue } }
    }
    @objc dynamic public var acceptsMouseMovedEvents: Bool {
      get { MainThread.sync { mouseMovementAccepted } }
      set { MainThread.sync { mouseMovementAccepted = newValue } }
    }

    @objc dynamic public var firstResponder: NSResponder? { MainThread.sync { responder } }
    @objc dynamic public var isVisible: Bool { MainThread.sync { visible } }
    @objc dynamic public var isKeyWindow: Bool { MainThread.sync { key } }
    @objc dynamic public var isMainWindow: Bool { MainThread.sync { main } }
    @objc dynamic public var canBecomeKeyWindow: Bool { true }
    @objc dynamic public var canBecomeMainWindow: Bool { true }
    @objc dynamic public var frame: CGRect { NSScreen.main.frame }
    @objc dynamic public var contentLayoutRect: CGRect { CGRect(origin: .zero, size: frame.size) }
    @objc dynamic public var screen: NSScreen { NSScreen.main }
    @objc dynamic public var backingScaleFactor: CGFloat { screen.backingScaleFactor }

    // The supported iPhone window is borderless and fills its scene.
    @objc dynamic public func contentRectForFrameRect(_ rect: CGRect) -> CGRect { rect }
    @objc dynamic public func frameRectForContentRect(_ rect: CGRect) -> CGRect { rect }
    @objc dynamic public func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
    @objc dynamic public func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    @objc(setFrame:display:animate:) dynamic public func setFrame(
      _ frame: CGRect, display: Bool, animate: Bool
    ) {}
    @objc(setFrame:display:) dynamic public func setFrame(_ frame: CGRect, display: Bool) {}
    @objc dynamic public func setContentSize(_ size: CGSize) {}
    @objc dynamic public func setFrameOrigin(_ origin: CGPoint) {}
    @objc dynamic public func setContentAspectRatio(_ ratio: CGSize) {}
    @objc dynamic public func center() {}
    @objc dynamic public func setOpaque(_ opaque: Bool) {}
    @objc dynamic public func setLevel(_ level: Int) {}
    @objc dynamic public func setCollectionBehavior(_ behavior: UInt) {}
    @objc dynamic public func miniaturize(_ sender: Any?) {}
    @objc dynamic public func deminiaturize(_ sender: Any?) {}
    @objc dynamic public func zoom(_ sender: Any?) {}

    @objc dynamic public func makeFirstResponder(_ candidate: NSResponder?) -> Bool {
      MainThread.sync {
        if responder === candidate || (candidate == nil && responder === self) { return true }
        guard responder?.resignFirstResponder() != false else { return false }
        responder = candidate
        if candidate == nil || candidate?.becomeFirstResponder() != true { responder = self }
        return true
      }
    }

    @objc dynamic public func makeKeyAndOrderFront(_ sender: Any?) {
      MainThread.sync {
        register()
        visible = true
        uiWindow.makeKeyAndVisible()
        becomeKey()
      }
    }

    @objc dynamic public func orderOut(_ sender: Any?) {
      MainThread.sync {
        visible = false
        uiWindow.isHidden = true
        resignKey()
        resignMain()
        if NSApplication.shared.keyWindow == nil,
          let next = NSApplication.shared.windowList.last(where: { $0 !== self && $0.isVisible })
        {
          next.uiWindow.makeKey()
          next.becomeKey()
        }
      }
    }

    @objc(setIsVisible:) dynamic public func setIsVisible(_ isVisible: Bool) {
      if isVisible { makeKeyAndOrderFront(nil) } else { orderOut(nil) }
    }

    @objc dynamic public func makeMainWindow() {
      MainThread.sync {
        guard !main else { return }
        if let previous = NSApplication.shared.mainWindow, previous !== self {
          previous.resignMain()
        }
        main = true
        NSApplication.shared.mainWindow = self
        notify("NSWindowDidBecomeMainNotification", delegate: "windowDidBecomeMain:")
      }
    }

    @objc(invalidateCursorRectsForView:) dynamic public func invalidateCursorRects(for view: NSView)
    {
      MainThread.async {
        view.discardCursorRects()
        view.resetCursorRects()
      }
    }

    @objc dynamic public func toggleFullScreen(_ sender: Any?) {
      MainThread.sync {
        let entering = style & Self.fullScreenStyle == 0
        notify(
          entering
            ? "NSWindowWillEnterFullScreenNotification" : "NSWindowWillExitFullScreenNotification",
          delegate: entering ? "windowWillEnterFullScreen:" : "windowWillExitFullScreen:")
        style ^= Self.fullScreenStyle
        MainThread.async {
          self.notify(
            entering
              ? "NSWindowDidEnterFullScreenNotification" : "NSWindowDidExitFullScreenNotification",
            delegate: entering ? "windowDidEnterFullScreen:" : "windowDidExitFullScreen:")
        }
      }
    }

    @objc dynamic public func close() {
      MainThread.sync {
        guard !closing, NSApplication.shared.windowList.contains(where: { $0 === self }) else {
          return
        }
        closing = true
        defer { closing = false }
        notify("NSWindowWillCloseNotification", delegate: "windowWillClose:")
        orderOut(nil)
        NSApplication.shared.windowList.removeAll { $0 === self }
      }
    }

    @MainActor final func detachFirstResponder(in view: NSView) {
      guard view.containsResponder(responder) else { return }
      _ = responder?.resignFirstResponder()
      responder = self
      _ = becomeFirstResponder()
    }

    @MainActor final func becomeKey() {
      register()
      if !key {
        if let previous = NSApplication.shared.keyWindow, previous !== self { previous.resignKey() }
        key = true
        NSApplication.shared.keyWindow = self
        if responder == nil {
          _ = makeFirstResponder(content?.acceptsFirstResponder == true ? content : nil)
        }
        notify("NSWindowDidBecomeKeyNotification", delegate: "windowDidBecomeKey:")
      }
      makeMainWindow()
    }

    @MainActor final func resignKey() {
      guard key else { return }
      key = false
      if NSApplication.shared.keyWindow === self { NSApplication.shared.keyWindow = nil }
      notify("NSWindowDidResignKeyNotification", delegate: "windowDidResignKey:")
    }

    @MainActor final func contentDidResize() {
      notify("NSWindowDidResizeNotification", delegate: "windowDidResize:")
    }

    @MainActor final private func resignMain() {
      guard main else { return }
      main = false
      if NSApplication.shared.mainWindow === self { NSApplication.shared.mainWindow = nil }
      notify("NSWindowDidResignMainNotification", delegate: "windowDidResignMain:")
    }

    @MainActor final private func register() {
      guard !NSApplication.shared.windowList.contains(where: { $0 === self }) else { return }
      NSApplication.shared.windowList.append(self)
    }

    @MainActor final private func notify(_ name: String, delegate selectorName: String) {
      let notification = Notification(name: Notification.Name(name), object: self)
      NotificationCenter.default.post(notification)
      let selector = NSSelectorFromString(selectorName)
      if let delegate = observer, delegate.responds(to: selector) {
        _ = delegate.perform(selector, with: notification)
      }
    }
  }

  final class GameRootViewController: UIViewController {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersPointerLocked: Bool { Gameplay.isPointerLocked }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
  }
#endif
