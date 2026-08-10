#if os(iOS)
  import Foundation

  @objc(NSWindowController)
  public class NSWindowController: NSResponder {
    final private var storedWindow: NSWindow?

    @objc(initWithWindow:) dynamic public init(window: NSWindow?) {
      storedWindow = window
      super.init()
      window?.windowController = self
    }

    @objc public override convenience init() { self.init(window: nil) }

    @objc dynamic public var window: NSWindow? {
      get { storedWindow }
      set {
        storedWindow = newValue
        newValue?.windowController = self
      }
    }

    @objc dynamic public func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    @objc dynamic public func windowDidLoad() {}
    @objc dynamic public func close() { window?.close() }
  }
#endif
