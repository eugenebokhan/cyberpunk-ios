#if os(iOS)
  import UIKit

  @objc(NSMenu)
  public final class NSMenu: NSObject {
    @objc public class var menuBarVisible: Bool { false }
    // UIKit has no desktop menu bar for this request to show or hide.
    @objc public class func setMenuBarVisible(_ visible: Bool) {}
  }

  @objc(NSWorkspace)
  public final class NSWorkspace: NSObject {
    @objc(sharedWorkspace) public static let shared = NSWorkspace()

    @objc(openURL:) public func open(_ url: URL) -> Bool {
      guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return false
      }
      MainThread.async {
        UIApplication.shared.open(url) { opened in
          if !opened { RuntimeLog.write("iOS declined the requested web URL") }
        }
      }
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

  @objc(GKDialogController)
  public final class GKDialogController: NSObject {
    @objc(sharedDialogController) public static let shared = GKDialogController()
    @objc public weak var parentWindow: NSWindow?
    private weak var activeController: UIViewController?

    @objc(presentViewController:) public func present(_ value: AnyObject) -> Bool {
      guard let controller = value as? UIViewController else { return false }
      return MainThread.sync {
        var presenter =
          parentWindow?.uiWindow.rootViewController
          ?? GameApplicationDelegate.scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = presenter?.presentedViewController { presenter = next }
        guard let presenter, presenter.viewIfLoaded?.window != nil,
          !presenter.isBeingDismissed, controller.presentingViewController == nil
        else { return false }
        presenter.present(controller, animated: true)
        activeController = controller
        return true
      }
    }

    @objc(dismiss:) public func dismiss(_ sender: Any?) {
      MainThread.sync {
        activeController?.dismiss(animated: true)
        activeController = nil
      }
    }
  }

  enum AppKitDrawing {
    static func install() {
      guard let colorClass = object_getClass(UIColor.self) else {
        preconditionFailure("UIColor has no Objective-C metaclass")
      }
      let focusColor: @convention(block) (AnyObject) -> UIColor = { _ in .systemBlue }
      ObjectiveCRuntime.addIfMissing(
        colorClass, NSSelectorFromString("keyboardFocusIndicatorColor"), types: "@@:",
        block: focusColor)
    }
  }

  @_cdecl("NSRectFill")
  public func nsRectFill(_ rectangle: CGRect) { UIRectFill(rectangle) }
#endif
