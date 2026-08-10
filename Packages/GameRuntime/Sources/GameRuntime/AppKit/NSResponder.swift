#if os(iOS)
  import Foundation

  // The game subclasses the AppKit classes below (its window, views, buttons and scroller). An
  // Objective-C subclass of a Swift class has no Swift vtable, so their members are `@objc
  // dynamic`, which also lets the game's overrides run, and Swift-only storage is `final`.

  @objc(NSResponder)
  public class NSResponder: NSObject {
    @objc dynamic public weak var nextResponder: NSResponder?
    @objc dynamic public var acceptsFirstResponder: Bool { false }
    @objc dynamic public func becomeFirstResponder() -> Bool { true }
    @objc dynamic public func resignFirstResponder() -> Bool { true }
  }
#endif
