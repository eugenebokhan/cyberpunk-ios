#if os(iOS)
  import Foundation

  @objc(NSWindowController)
  public class NSWindowController: NSResponder {
    final private var managedWindow: NSWindow?

    @objc(initWithWindow:) dynamic public init(window: NSWindow?) {
      super.init()
      self.window = window
      nextResponder = NSApplication.shared
    }

    @objc public override convenience init() { self.init(window: nil) }

    @objc dynamic public var window: NSWindow? {
      get { MainThread.sync { managedWindow } }
      set {
        MainThread.sync {
          guard managedWindow !== newValue else { return }
          if managedWindow?.windowController === self { managedWindow?.windowController = nil }
          managedWindow = newValue
          newValue?.windowController = self
        }
      }
    }

    @objc dynamic public func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    // Subclasses are notified after loading their own window.
    @objc dynamic public func windowDidLoad() {}
    @objc dynamic public func close() { window?.close() }
  }
#endif
