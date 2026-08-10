#if os(iOS)
  import UIKit

  /// iOS has no menu bar.
  @objc(NSMenu)
  public final class NSMenu: NSObject {
    @objc public class var menuBarVisible: Bool { false }
    @objc public class func setMenuBarVisible(_ visible: Bool) {}
  }

  /// Web links open in the browser, which always handles them. Whether another app handles some
  /// other scheme is only known after iOS tries asynchronously, so those report failure.
  @objc(NSWorkspace)
  public final class NSWorkspace: NSObject {
    @objc(sharedWorkspace) public static let shared = NSWorkspace()

    @objc(openURL:) public func open(_ url: URL) -> Bool {
      guard ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
      MainThread.async { UIApplication.shared.open(url) }
      return true
    }
  }

  @objc(NSTrackingArea)
  public final class NSTrackingArea: NSObject {
    @objc public let rect: CGRect
    @objc public let options: UInt
    @objc public weak var owner: AnyObject?
    @objc public let userInfo: [AnyHashable: Any]?

    @objc(initWithRect:options:owner:userInfo:)
    public init(rect: CGRect, options: UInt, owner: AnyObject?, userInfo: [AnyHashable: Any]?) {
      self.rect = rect
      self.options = options
      self.owner = owner
      self.userInfo = userInfo
    }
  }

  /// AppKit paths are UIKit paths; UIKit drawing serves the game's `drawRect:`.
  @objc(NSBezierPath)
  public final class NSBezierPath: NSObject {
    @objc(bezierPathWithRoundedRect:xRadius:yRadius:)
    public class func bezierPath(roundedRect rect: CGRect, xRadius: CGFloat, yRadius: CGFloat)
      -> UIBezierPath
    {
      UIBezierPath(
        roundedRect: rect, byRoundingCorners: .allCorners,
        cornerRadii: CGSize(width: xRadius, height: yRadius))
    }
  }

  /// Game Center views from GameServices, presented over the game.
  @objc(GKDialogController)
  public final class GKDialogController: NSObject {
    @objc(sharedDialogController) public static let shared = GKDialogController()
    @objc public weak var parentWindow: NSWindow?
    private weak var presented: UIViewController?

    @objc(presentViewController:) public func present(_ controller: AnyObject) -> Bool {
      guard let controller = controller as? UIViewController else { return false }
      return MainThread.sync {
        var host =
          parentWindow?.uiWindow.rootViewController
          ?? GameApplicationDelegate.scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = host?.presentedViewController { host = presented }
        guard let host, !host.isBeingDismissed, controller.presentingViewController == nil else {
          return false
        }
        host.present(controller, animated: true)
        presented = controller
        return true
      }
    }

    @objc(dismiss:) public func dismiss(_ sender: Any?) {
      MainThread.sync {
        presented?.dismiss(animated: true)
        presented = nil
      }
    }
  }

  /// AppKit drawing functions and colors the game uses on top of UIKit.
  enum AppKitDrawing {
    /// NSColor is UIColor in the retargeted game; AppKit's focus ring color is the tint.
    static func install() {
      let color: @convention(block) (AnyObject) -> UIColor = { _ in .systemBlue }
      ObjectiveCRuntime.addIfMissing(
        object_getClass(UIColor.self)!, Selector(("keyboardFocusIndicatorColor")), types: "@@:",
        block: color)
    }
  }

  @_cdecl("NSRectFill")
  public func nsRectFill(_ rect: CGRect) { UIRectFill(rect) }
#endif
