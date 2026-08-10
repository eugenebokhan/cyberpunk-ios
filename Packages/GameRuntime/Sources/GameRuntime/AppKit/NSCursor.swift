#if os(iOS)
  import Foundation
  import Synchronization

  /// AppKit cursors. iOS draws the pointer itself and cannot show an image cursor, so cursors
  /// keep their image for the game while hiding the cursor is what changes on screen.
  @objc(NSCursor)
  public final class NSCursor: NSObject {
    private static let stack = Mutex<[NSCursor]>([])
    private static let active = Mutex<NSCursor?>(nil)

    @objc public let image: NSImage?
    @objc public let hotSpot: CGPoint

    @objc(initWithImage:hotSpot:) public init(image: NSImage?, hotSpot: CGPoint) {
      self.image = image
      self.hotSpot = hotSpot
    }

    @objc(arrowCursor) public static let arrow = NSCursor(image: nil, hotSpot: .zero)
    @objc public class var pointingHandCursor: NSCursor { arrow }
    @objc(IBeamCursor) public class var iBeamCursor: NSCursor { arrow }
    @objc public class var currentCursor: NSCursor { active.withLock { $0 } ?? arrow }

    /// The game hides the cursor in gameplay and shows it in menus.
    @objc public class func hide() { Gameplay.setCursorHidden(true) }
    @objc public class func unhide() { Gameplay.setCursorHidden(false) }
    @objc public class func setHiddenUntilMouseMoves(_ flag: Bool) {}

    @objc public func set() { Self.active.withLock { $0 = self } }

    @objc public func push() {
      Self.stack.withLock { $0.append(Self.currentCursor) }
      set()
    }

    @objc public class func pop() {
      guard let previous = stack.withLock({ $0.popLast() }) else { return }
      previous.set()
    }
  }
#endif
