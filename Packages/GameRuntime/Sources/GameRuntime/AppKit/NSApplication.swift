#if os(iOS)
  import GameRuntimeABI
  import Synchronization
  import UIKit

  @objc(NSApplication)
  public final class NSApplication: NSResponder {
    static let shared: NSApplication = {
      let application = NSApplication()
      NSApp = Unmanaged.passUnretained(application).toOpaque()
      return application
    }()

    private var registeredWindows: [NSWindow] = []
    private weak var applicationDelegate: AnyObject?
    private weak var key: NSWindow?
    private weak var main: NSWindow?
    private var active = false
    private var activationPending = false
    private var launched = false
    private var policy = 0
    private var idleTimerDisabled = false
    private let running = Atomic(true)
    private let eventsAvailable = NSCondition()
    private var events = AppKitEventQueue<NSEvent>()

    final var windowList: [NSWindow] {
      get { MainThread.sync { registeredWindows } }
      set { MainThread.sync { registeredWindows = newValue } }
    }

    @objc public class var sharedApplication: NSApplication {
      if Thread.isMainThread, GameBoot.isCalledFromGameMain() { GameBoot.startUIKit() }
      return shared
    }

    @objc public var delegate: AnyObject? {
      get { MainThread.sync { applicationDelegate } }
      set {
        MainThread.sync {
          applicationDelegate = newValue
          if newValue != nil, activationPending {
            activationPending = false
            MainThread.async { self.becomeActive(true) }
          }
        }
      }
    }

    @objc public var presentationOptions: UInt = 0
    @objc public var mainMenu: AnyObject?
    @objc public var keyWindow: NSWindow? {
      get { MainThread.sync { key } }
      set { MainThread.sync { key = newValue } }
    }
    @objc public var mainWindow: NSWindow? {
      get { MainThread.sync { main } }
      set { MainThread.sync { main = newValue } }
    }
    @objc public var windows: [NSWindow] { windowList }
    @objc public var orderedWindows: [NSWindow] {
      MainThread.sync { registeredWindows.reversed().filter(\.isVisible) }
    }
    @objc public var isActive: Bool { MainThread.sync { active } }
    @objc public var isHidden: Bool { false }
    @objc public var isRunning: Bool { running.load(ordering: .acquiring) }
    @objc public var activationPolicy: Int { MainThread.sync { policy } }

    @objc public func setActivationPolicy(_ activationPolicy: Int) -> Bool {
      MainThread.sync { policy = activationPolicy }
      return true
    }

    // Process activation and hiding are controlled by iOS, not the desktop window manager.
    @objc public func activateIgnoringOtherApps(_ flag: Bool) {}
    @objc public func hide(_ sender: Any?) {}
    @objc public func unhide(_ sender: Any?) {}
    @objc public func hideOtherApplications(_ sender: Any?) {}

    @objc public func stop(_ sender: Any?) {
      running.store(false, ordering: .releasing)
      eventsAvailable.lock()
      eventsAvailable.broadcast()
      eventsAvailable.unlock()
      CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    @objc public func finishLaunching() {
      MainThread.sync {
        guard !launched else { return }
        launched = true
        let will = Notification(
          name: Notification.Name("NSApplicationWillFinishLaunchingNotification"), object: self)
        let did = Notification(
          name: Notification.Name("NSApplicationDidFinishLaunchingNotification"), object: self)
        tellDelegate("applicationWillFinishLaunching:", will)
        NotificationCenter.default.post(will)
        tellDelegate("applicationDidFinishLaunching:", did)
        NotificationCenter.default.post(did)
        RuntimeLog.write("application launch callbacks completed")
      }
    }

    @objc public func run() {
      precondition(Thread.isMainThread, "the application event loop must run on the main thread")
      running.store(true, ordering: .releasing)
      finishLaunching()
      MainThread.async {
        if UIApplication.shared.applicationState == .active { self.becomeActive(true) }
      }
      while isRunning {
        if let event = nextEvent(
          matching: UInt64.max, until: .distantFuture,
          inMode: RunLoop.Mode.default.rawValue, dequeue: true)
        {
          sendEvent(event)
        }
      }
    }

    @objc public func terminate(_ sender: Any?) {
      willTerminate()
      exit(0)
    }

    final func willTerminate() {
      MainThread.sync { tellDelegate("applicationWillTerminate:", nil) }
    }

    @objc(nextEventMatchingMask:untilDate:inMode:dequeue:)
    public func nextEvent(
      matching mask: UInt64, until date: Date?, inMode mode: String?, dequeue: Bool
    ) -> NSEvent? {
      let expiration = date ?? .distantPast
      if !Thread.isMainThread {
        eventsAvailable.lock()
        defer { eventsAvailable.unlock() }
        while true {
          if let event = events.next(matching: mask, dequeue: dequeue) { return event }
          guard isRunning, expiration.timeIntervalSinceNow > 0,
            eventsAvailable.wait(until: expiration)
          else { return nil }
        }
      }

      let runLoopMode = CFRunLoopMode(rawValue: (mode ?? RunLoop.Mode.default.rawValue) as CFString)
      repeat {
        if let event = takeEvent(matching: mask, dequeue: dequeue) { return event }
        let remaining = max(0, expiration.timeIntervalSinceNow)
        let result = MainActor.assumeIsolated {
          pumpRunLoop(mode: runLoopMode, wait: min(remaining, 0.1))
        }
        if let event = takeEvent(matching: mask, dequeue: dequeue) { return event }
        if result == .finished || result == .stopped { return nil }
      } while isRunning && expiration.timeIntervalSinceNow > 0
      return nil
    }

    @objc(postEvent:atStart:) public func post(_ event: NSEvent, atStart: Bool) {
      eventsAvailable.lock()
      events.post(event, type: event.type, atStart: atStart)
      eventsAvailable.broadcast()
      eventsAvailable.unlock()
      CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    @objc public func sendEvent(_ event: NSEvent) {
      MainThread.sync {
        guard let delivered = NSEvent.monitored(event),
          let selector = delivered.responderSelector
        else { return }
        let window = delivered.window ?? key ?? registeredWindows.last(where: \.isVisible)
        var responder: NSResponder?
        if delivered.isKeyboardEvent {
          responder = window?.firstResponder ?? window
        } else {
          responder = window?.contentView?.hitView(at: delivered.locationInWindow) ?? window
        }
        if let recipient = target(for: selector, startingAt: responder) {
          _ = recipient.perform(selector, with: delivered)
        }
      }
    }

    // UIKit and virtual-controller producers deliver immediately without going through a second queue.
    final func dispatch(_ event: NSEvent) { sendEvent(event) }

    final func sendAction(
      _ selector: Selector, to explicitTarget: AnyObject?, from sender: AnyObject
    )
      -> Bool
    {
      MainThread.sync {
        let recipient: AnyObject? =
          explicitTarget
          ?? actionTarget(in: key, for: selector)
          ?? (main === key ? nil : actionTarget(in: main, for: selector))
          ?? (responds(to: selector) ? self : nil)
          ?? (applicationDelegate?.responds(to: selector) == true ? applicationDelegate : nil)
        guard let recipient, recipient.responds(to: selector) else { return false }
        _ = recipient.perform(selector, with: sender)
        return true
      }
    }

    @MainActor final func becomeActive(_ isActive: Bool) {
      guard applicationDelegate != nil || !isActive else {
        activationPending = true
        return
      }
      if !isActive { activationPending = false }
      guard active != isActive else { return }
      active = isActive
      let will = Notification(
        name: Notification.Name(
          isActive
            ? "NSApplicationWillBecomeActiveNotification"
            : NSApplicationWillResignActiveNotification as String), object: self)
      let did = Notification(
        name: Notification.Name(
          (isActive
            ? NSApplicationDidBecomeActiveNotification : NSApplicationDidResignActiveNotification)
            as String), object: self)
      NotificationCenter.default.post(will)
      tellDelegate(isActive ? "applicationWillBecomeActive:" : "applicationWillResignActive:", will)
      if isActive {
        let candidate = key?.isVisible == true ? key : registeredWindows.last(where: \.isVisible)
        if let candidate {
          candidate.uiWindow.makeKey()
          candidate.becomeKey()
        }
      } else {
        for window in registeredWindows { window.resignKey() }
      }
      NotificationCenter.default.post(did)
      tellDelegate(isActive ? "applicationDidBecomeActive:" : "applicationDidResignActive:", did)
    }

    @MainActor private func actionTarget(in window: NSWindow?, for selector: Selector) -> AnyObject?
    {
      if let responder = target(
        for: selector, startingAt: window?.firstResponder ?? window, stoppingAtApplication: true)
      {
        return responder
      }
      guard let delegate = window?.delegate, delegate.responds(to: selector) else { return nil }
      return delegate
    }

    @MainActor private func target(
      for selector: Selector, startingAt first: NSResponder?, stoppingAtApplication: Bool = false
    ) -> NSResponder? {
      var current = first
      var visited = Set<ObjectIdentifier>()
      while let responder = current, visited.insert(ObjectIdentifier(responder)).inserted {
        if stoppingAtApplication && responder === self { return nil }
        if responder.responds(to: selector) { return responder }
        current = responder.nextResponder
      }
      return nil
    }

    private func takeEvent(matching mask: UInt64, dequeue: Bool) -> NSEvent? {
      eventsAvailable.lock()
      defer { eventsAvailable.unlock() }
      return events.next(matching: mask, dequeue: dequeue)
    }

    @MainActor private func pumpRunLoop(mode: CFRunLoopMode, wait: TimeInterval)
      -> CFRunLoopRunResult
    {
      if BackgroundSuspension.isInBackground {
        while BackgroundSuspension.isInBackground && isRunning {
          autoreleasepool {
            _ = CFRunLoopRunInMode(.defaultMode, 0.5, false)
            _dispatch_main_queue_callback_4CF(nil)
          }
        }
      }
      if !idleTimerDisabled {
        idleTimerDisabled = true
        UIApplication.shared.isIdleTimerDisabled = true
      }
      CDPRSession.restoreIfNeeded()
      var count = 0
      var result = CFRunLoopRunInMode(mode, wait, true)
      while result == .handledSource, count < 64 {
        result = CFRunLoopRunInMode(mode, 0, true)
        count += 1
      }
      return result
    }

    @MainActor private func tellDelegate(_ name: String, _ notification: Notification?) {
      let selector = NSSelectorFromString(name)
      guard let delegate = applicationDelegate, delegate.responds(to: selector) else { return }
      _ = delegate.perform(selector, with: notification)
    }
  }
#endif
