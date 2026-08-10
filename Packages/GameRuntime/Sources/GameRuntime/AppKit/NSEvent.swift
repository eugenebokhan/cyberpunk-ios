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

    /// A local event monitor: the game's handler for the event kinds in its mask.
    final class Monitor: NSObject {
      let mask: UInt64
      let handler: (NSEvent) -> NSEvent?

      init(mask: UInt64, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
      }
    }

    private static let monitors = Mutex<[Monitor]>([])
    private static let location = Mutex(CGPoint.zero)

    /// The AppKit cursor position, bottom-left origin.
    static var cursorLocation: CGPoint {
      get { location.withLock { $0 } }
      set { location.withLock { $0 = newValue } }
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
      let monitor = Monitor(mask: mask, handler: handler)
      monitors.withLock { $0.append(monitor) }
      return monitor
    }

    @objc public class func removeMonitor(_ monitor: AnyObject) {
      monitors.withLock { $0.removeAll { $0 === monitor } }
    }

    /// Mouse events are delivered as they arrive; there is nothing to coalesce.
    @objc public class func setMouseCoalescingEnabled(_ enabled: Bool) {}

    /// A key event for a Mac virtual key code (53 is Escape).
    static func key(_ keyCode: UInt16, characters: String, pressed: Bool) -> NSEvent {
      let event = NSEvent()
      event.type = (pressed ? Kind.keyDown : Kind.keyUp).rawValue
      event.keyCode = keyCode
      event.characters = characters
      event.charactersIgnoringModifiers = characters
      event.locationInWindow = cursorLocation
      event.timestamp = CACurrentMediaTime()
      return event
    }

    /// `event` after the game's monitors, or nil when one of them consumed it.
    static func monitored(_ event: NSEvent) -> NSEvent? {
      var event = event
      for monitor in monitors.withLock({ $0 }) where monitor.mask & (1 << event.type) != 0 {
        guard let next = monitor.handler(event) else { return nil }
        event = next
      }
      return event
    }

    var isKeyboardEvent: Bool {
      [.keyDown, .keyUp, .flagsChanged].contains(Kind(rawValue: type))
    }

    var responderSelector: Selector? {
      switch Kind(rawValue: type) {
      case .leftMouseDown: Selector(("mouseDown:"))
      case .leftMouseUp: Selector(("mouseUp:"))
      case .rightMouseDown: Selector(("rightMouseDown:"))
      case .rightMouseUp: Selector(("rightMouseUp:"))
      case .mouseMoved: Selector(("mouseMoved:"))
      case .leftMouseDragged: Selector(("mouseDragged:"))
      case .rightMouseDragged: Selector(("rightMouseDragged:"))
      case .mouseEntered: Selector(("mouseEntered:"))
      case .mouseExited: Selector(("mouseExited:"))
      case .keyDown: Selector(("keyDown:"))
      case .keyUp: Selector(("keyUp:"))
      case .flagsChanged: Selector(("flagsChanged:"))
      case .scrollWheel: Selector(("scrollWheel:"))
      case .otherMouseDown: Selector(("otherMouseDown:"))
      case .otherMouseUp: Selector(("otherMouseUp:"))
      case .otherMouseDragged: Selector(("otherMouseDragged:"))
      case nil: nil
      }
    }
  }
#endif
