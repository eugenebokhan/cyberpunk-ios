#if os(iOS)
  import GameRuntimeABI
  import UIKit

  /// An AppKit window shown as a full-screen UIKit window in the app scene.
  @objc(NSWindow)
  public class NSWindow: NSResponder {
    private static let fullScreenStyle: UInt = 1 << 14

    final private(set) var uiWindow: UIWindow!
    final private var storedFrame: CGRect
    final private var storedContentView: NSView?
    final private var storedFirstResponder: NSResponder?
    final private var storedStyleMask: UInt
    final private var storedMinSize = CGSize.zero
    final private var storedAcceptsMouseMovedEvents = false
    final private var storedTitle: String?
    final private var visible = false
    final private var key = false
    final private var main = false
    final private weak var storedDelegate: AnyObject?
    final private weak var storedWindowController: AnyObject?

    @objc(initWithContentRect:styleMask:backing:defer:screen:)
    dynamic public init(
      contentRect: CGRect, styleMask: UInt, backing: UInt, defer deferCreation: Bool,
      screen: NSScreen?
    ) {
      storedStyleMask = styleMask
      storedFrame = NSScreen.main.frame
      super.init()
      uiWindow = MainThread.sync {
        guard let scene = GameApplicationDelegate.scene else {
          preconditionFailure("the game created a window before the app scene connected")
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = GameRootViewController()
        window.backgroundColor = .black
        return window
      }
      NSApplication.shared.windowList.append(self)
      RuntimeLog.write("game window created")
    }

    @objc(initWithContentRect:styleMask:backing:defer:)
    public convenience init(
      contentRect: CGRect, styleMask: UInt, backing: UInt, defer deferCreation: Bool
    ) {
      self.init(
        contentRect: contentRect, styleMask: styleMask, backing: backing, defer: deferCreation,
        screen: nil)
    }

    @objc public override convenience init() {
      self.init(contentRect: .zero, styleMask: 1, backing: 2, defer: false)
    }

    @objc dynamic public var contentView: NSView? {
      get { storedContentView }
      set {
        storedContentView = newValue
        guard let view = newValue else { return }
        view.hostingWindow = self
        MainThread.sync {
          let root = uiWindow.rootViewController!.view!
          view.host.frame = root.bounds
          view.host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          view.host.backgroundColor = .black
          root.addSubview(view.host)
          view.layoutFromHost()
        }
        view.viewDidMoveToWindow()
      }
    }

    @objc dynamic public var delegate: AnyObject? {
      get { storedDelegate }
      set { storedDelegate = newValue }
    }

    @objc dynamic public var windowController: AnyObject? {
      get { storedWindowController }
      set { storedWindowController = newValue }
    }

    @objc dynamic public var styleMask: UInt {
      get { storedStyleMask }
      set { storedStyleMask = newValue }
    }

    @objc dynamic public var title: String? {
      get { storedTitle }
      set { storedTitle = newValue }
    }

    @objc dynamic public var minSize: CGSize {
      get { storedMinSize }
      set { storedMinSize = newValue }
    }

    @objc dynamic public var acceptsMouseMovedEvents: Bool {
      get { storedAcceptsMouseMovedEvents }
      set { storedAcceptsMouseMovedEvents = newValue }
    }

    @objc dynamic public var firstResponder: NSResponder? { storedFirstResponder }
    @objc dynamic public var isVisible: Bool { visible }
    @objc dynamic public var isKeyWindow: Bool { key }
    @objc dynamic public var isMainWindow: Bool { main }
    @objc dynamic public var canBecomeKeyWindow: Bool { true }
    @objc dynamic public var canBecomeMainWindow: Bool { true }
    @objc dynamic public var frame: CGRect { storedFrame }
    @objc dynamic public var contentLayoutRect: CGRect {
      CGRect(origin: .zero, size: storedFrame.size)
    }
    @objc dynamic public var screen: NSScreen { NSScreen.main }
    @objc dynamic public var backingScaleFactor: CGFloat { NSScreen.main.backingScaleFactor }

    // The window fills the screen with no frame: content and frame rectangles and screen and
    // window coordinates coincide, and size, position, level and miniaturization requests do not
    // apply.
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

    @objc dynamic public func makeFirstResponder(_ responder: NSResponder?) -> Bool {
      guard storedFirstResponder !== responder else { return true }
      _ = storedFirstResponder?.resignFirstResponder()
      storedFirstResponder = responder
      _ = responder?.becomeFirstResponder()
      return true
    }

    @objc dynamic public func makeKeyAndOrderFront(_ sender: Any?) {
      visible = true
      MainThread.sync { uiWindow.makeKeyAndVisible() }
      becomeKey()
    }

    @objc dynamic public func orderOut(_ sender: Any?) {
      visible = false
      MainThread.sync { uiWindow.isHidden = true }
    }

    @objc(setIsVisible:) dynamic public func setIsVisible(_ isVisible: Bool) {
      if isVisible { makeKeyAndOrderFront(nil) } else { orderOut(nil) }
    }

    @objc dynamic public func makeMainWindow() {
      main = true
      NSApplication.shared.mainWindow = self
    }

    /// Cursor rectangles are rebuilt the AppKit way, by the view.
    @objc(invalidateCursorRectsForView:) dynamic public func invalidateCursorRects(for view: NSView)
    {
      MainThread.async {
        view.discardCursorRects()
        view.resetCursorRects()
      }
    }

    @objc dynamic public func toggleFullScreen(_ sender: Any?) {
      let entering = storedStyleMask & Self.fullScreenStyle == 0
      let name =
        entering
        ? "NSWindowWillEnterFullScreenNotification"
        : NSWindowWillExitFullScreenNotification as String
      let notification = Notification(name: Notification.Name(name), object: self)
      tellDelegate(
        entering ? "windowWillEnterFullScreen:" : "windowWillExitFullScreen:", notification)
      NotificationCenter.default.post(notification)
      storedStyleMask ^= Self.fullScreenStyle
      MainThread.async {
        self.tellDelegate(
          entering ? "windowDidEnterFullScreen:" : "windowDidExitFullScreen:", notification)
      }
    }

    @objc dynamic public func close() {
      tellDelegate("windowWillClose:", post(NSWindowWillCloseNotification))
      orderOut(nil)
      NSApplication.shared.windowList.removeAll { $0 === self }
    }

    final func becomeKey() {
      guard !key else { return }
      key = true
      main = true
      NSApplication.shared.keyWindow = self
      NSApplication.shared.mainWindow = self
      if storedFirstResponder == nil { storedFirstResponder = storedContentView }
      let notification = post(NSWindowDidBecomeKeyNotification)
      tellDelegate("windowDidBecomeKey:", notification)
      tellDelegate("windowDidBecomeMain:", notification)
    }

    final func resignKey() {
      guard key else { return }
      key = false
      tellDelegate("windowDidResignKey:", post(NSWindowDidResignKeyNotification))
    }

    final func contentDidResize() {
      tellDelegate("windowDidResize:", post(NSWindowDidResizeNotification))
    }

    final private func post(_ name: CFString) -> Notification {
      let notification = Notification(name: Notification.Name(name as String), object: self)
      NotificationCenter.default.post(notification)
      return notification
    }

    final private func tellDelegate(_ selector: String, _ notification: Notification) {
      guard let delegate = storedDelegate, delegate.responds(to: Selector((selector))) else {
        return
      }
      _ = delegate.perform(Selector((selector)), with: notification)
    }
  }

  /// The root of every game window.
  final class GameRootViewController: UIViewController {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersPointerLocked: Bool { Gameplay.isPointerLocked }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
  }
#endif
