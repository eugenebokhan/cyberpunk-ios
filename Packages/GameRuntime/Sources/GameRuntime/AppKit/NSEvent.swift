import Foundation

struct AppKitEventQueue<Event> {
  private var entries: [(mask: UInt64, event: Event)] = []

  mutating func post(_ event: Event, type: UInt, atStart: Bool) {
    precondition(type < UInt(UInt64.bitWidth), "event type does not fit an AppKit event mask")
    let entry = (UInt64(1) << type, event)
    if atStart { entries.insert(entry, at: 0) } else { entries.append(entry) }
  }

  mutating func next(matching mask: UInt64, dequeue: Bool) -> Event? {
    guard let index = entries.firstIndex(where: { $0.mask & mask != 0 }) else { return nil }
    return dequeue ? entries.remove(at: index).event : entries[index].event
  }
}

#if os(iOS)
  import QuartzCore
  import Synchronization

  @objc(NSEvent)
  public final class NSEvent: NSObject {
    enum Kind: UInt {
      case leftMouseDown = 1
      case leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved
      case leftMouseDragged, rightMouseDragged, mouseEntered, mouseExited, keyDown, keyUp
      case flagsChanged
      case scrollWheel = 22
      case otherMouseDown = 25
      case otherMouseUp, otherMouseDragged
    }

    final class Monitor: NSObject {
      let mask: UInt64
      let handler: (NSEvent) -> NSEvent?

      init(mask: UInt64, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
      }
    }

    private static let monitors = Mutex<[Monitor]>([])
    private static let pointer = Mutex(CGPoint.zero)

    static var cursorLocation: CGPoint {
      get { pointer.withLock { $0 } }
      set { pointer.withLock { $0 = newValue } }
    }

    @objc public var type: UInt = 0
    @objc public var modifierFlags: UInt = 0
    @objc public var buttonNumber = 0
    @objc public var clickCount = 0
    @objc public var locationInWindow = CGPoint.zero
    @objc public var keyCode: UInt16 = 0
    @objc public var characters: String?
    @objc public var charactersIgnoringModifiers: String?
    @objc public var scrollingDeltaX: CGFloat = 0
    @objc public var scrollingDeltaY: CGFloat = 0
    @objc public var deltaX: CGFloat = 0
    @objc public var deltaY: CGFloat = 0
    @objc public var hasPreciseScrollingDeltas = false
    @objc public var isARepeat = false
    @objc public var timestamp: TimeInterval = 0
    @objc public weak var window: NSWindow?

    @objc public class var mouseLocation: CGPoint { cursorLocation }

    @objc(addLocalMonitorForEventsMatchingMask:handler:)
    public class func addLocalMonitor(
      matching mask: UInt64, handler: @escaping (NSEvent) -> NSEvent?
    ) -> AnyObject {
      let token = Monitor(mask: mask, handler: handler)
      monitors.withLock { $0.append(token) }
      return token
    }

    @objc public class func removeMonitor(_ token: AnyObject) {
      monitors.withLock { $0.removeAll { $0 === token } }
    }

    // Input is never coalesced by this adapter.
    @objc public class func setMouseCoalescingEnabled(_ enabled: Bool) {}

    static func key(_ keyCode: UInt16, characters: String, pressed: Bool) -> NSEvent {
      let result = NSEvent()
      result.type = (pressed ? Kind.keyDown : Kind.keyUp).rawValue
      result.keyCode = keyCode
      result.characters = characters
      result.charactersIgnoringModifiers = characters
      result.locationInWindow = cursorLocation
      result.timestamp = CACurrentMediaTime()
      return result
    }

    static func monitored(_ original: NSEvent) -> NSEvent? {
      var current = original
      let installed = monitors.withLock { $0 }
      for monitor in installed {
        guard current.type < UInt(UInt64.bitWidth),
          monitor.mask & (UInt64(1) << current.type) != 0
        else { continue }
        guard let replacement = monitor.handler(current) else { return nil }
        current = replacement
      }
      return current
    }

    var isKeyboardEvent: Bool {
      type == Kind.keyDown.rawValue || type == Kind.keyUp.rawValue
        || type == Kind.flagsChanged.rawValue
    }

    var responderSelector: Selector? {
      let name: String
      switch Kind(rawValue: type) {
      case .leftMouseDown: name = "mouseDown:"
      case .leftMouseUp: name = "mouseUp:"
      case .rightMouseDown: name = "rightMouseDown:"
      case .rightMouseUp: name = "rightMouseUp:"
      case .mouseMoved: name = "mouseMoved:"
      case .leftMouseDragged: name = "mouseDragged:"
      case .rightMouseDragged: name = "rightMouseDragged:"
      case .mouseEntered: name = "mouseEntered:"
      case .mouseExited: name = "mouseExited:"
      case .keyDown: name = "keyDown:"
      case .keyUp: name = "keyUp:"
      case .flagsChanged: name = "flagsChanged:"
      case .scrollWheel: name = "scrollWheel:"
      case .otherMouseDown: name = "otherMouseDown:"
      case .otherMouseUp: name = "otherMouseUp:"
      case .otherMouseDragged: name = "otherMouseDragged:"
      case nil: return nil
      }
      return NSSelectorFromString(name)
    }
  }
#endif
