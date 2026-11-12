#if os(iOS)
  import Foundation
  import Synchronization

  @objc(NSCursor)
  public final class NSCursor: NSObject {
    private static let selection = Mutex(
      (current: Optional<NSCursor>.none, previous: [NSCursor]()))

    @objc public let image: NSImage?
    @objc public let hotSpot: CGPoint

    @objc(initWithImage:hotSpot:) public init(image: NSImage?, hotSpot: CGPoint) {
      self.image = image
      self.hotSpot = hotSpot
    }

    @objc(arrowCursor) public static let arrow = NSCursor(image: nil, hotSpot: .zero)
    @objc public class var pointingHandCursor: NSCursor { arrow }
    @objc(IBeamCursor) public class var iBeamCursor: NSCursor { arrow }
    @objc public class var currentCursor: NSCursor { selection.withLock { $0.current } ?? arrow }

    @objc public class func hide() { Gameplay.setCursorHidden(true) }
    @objc public class func unhide() { Gameplay.setCursorHidden(false) }

    // The system pointer's temporary visibility is managed by UIKit.
    @objc public class func setHiddenUntilMouseMoves(_ flag: Bool) {}

    @objc public func set() { Self.selection.withLock { $0.current = self } }

    @objc public func push() {
      Self.selection.withLock {
        $0.previous.append($0.current ?? Self.arrow)
        $0.current = self
      }
    }

    @objc public class func pop() {
      selection.withLock {
        if let previous = $0.previous.popLast() { $0.current = previous }
      }
    }
  }
#endif
