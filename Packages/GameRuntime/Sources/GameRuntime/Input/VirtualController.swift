#if os(iOS)
  import GameController
  import GamepadFeature
  import Synchronization

  /// The touch gamepad as a GameController device. The game finds it among the controllers like
  /// hardware and reads it as an Xbox controller. Writes to its snapshot elements do not call the
  /// game's handlers, so the runtime runs them. A hardware controller, such as a Backbone, takes
  /// over while it is connected.
  final class VirtualController: @unchecked Sendable {
    private typealias ButtonHandler =
      @convention(block) (GCControllerButtonInput, Float, Bool) -> Void
    private typealias PadHandler =
      @convention(block) (GCControllerDirectionPad, Float, Float) -> Void
    private typealias AxisHandler = @convention(block) (GCControllerAxisInput, Float) -> Void
    private typealias GamepadHandler =
      @convention(block) (GCExtendedGamepad, GCControllerElement) -> Void

    /// Installed once on the main thread, before the game starts.
    nonisolated(unsafe) static private(set) var shared: VirtualController?

    let controller: GCController
    private let gamepad: GCExtendedGamepad
    private let hardware: () -> [GCController]
    private let elements: Set<ObjectIdentifier>
    private let handlers = Mutex(NSMapTable<AnyObject, AnyObject>.weakToStrongObjects())
    private let hardwareConnected = Atomic(false)
    private let hardwareHandled = Atomic(false)
    @MainActor private var directions: Set<GamepadButton> = []
    @MainActor private var generation = 0

    var isHardwareConnected: Bool { hardwareConnected.load(ordering: .relaxed) }

    private init(
      controller: GCController, gamepad: GCExtendedGamepad, hardware: @escaping () -> [GCController]
    ) {
      self.controller = controller
      self.gamepad = gamepad
      self.hardware = hardware
      var elements: Set<ObjectIdentifier> = [ObjectIdentifier(gamepad)]
      for element in gamepad.allElements {
        elements.insert(ObjectIdentifier(element))
        if let pad = element as? GCControllerDirectionPad {
          for part in [pad.xAxis, pad.yAxis, pad.up, pad.down, pad.left, pad.right] as [AnyObject] {
            elements.insert(ObjectIdentifier(part))
          }
        }
      }
      self.elements = elements
      hardwareConnected.store(!hardware().isEmpty, ordering: .relaxed)
    }

    @MainActor static func install() -> VirtualController? {
      let controller = GCController.withExtendedGamepad()
      let selector = #selector(GCController.controllers)
      guard let gamepad = controller.extendedGamepad,
        let metaclass = object_getClass(GCController.self),
        let method = class_getInstanceMethod(metaclass, selector)
      else {
        RuntimeLog.write("touch gamepad: no virtual controller")
        return nil
      }
      controller.playerIndex = .index1
      typealias List = @convention(c) (AnyObject, Selector) -> NSArray
      let controllers = unsafeBitCast(method_getImplementation(method), to: List.self)
      let virtual = VirtualController(controller: controller, gamepad: gamepad) {
        (controllers(GCController.self, selector) as? [GCController] ?? []).filter {
          !$0.isSnapshot
        }
      }
      shared = virtual
      virtual.presentToGame(metaclass, controllers: controllers)
      virtual.observeGameHandlers()
      virtual.observeHardware()
      return virtual
    }

    // MARK: Touch input

    @MainActor func set(_ button: GamepadButton, pressed: Bool) {
      switch button {
      case .pause:
        // Pause is Escape on the Mac.
        NSApplication.shared.dispatch(NSEvent.key(53, characters: "\u{1b}", pressed: pressed))
      case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
        if pressed { directions.insert(button) } else { directions.remove(button) }
        func axis(_ positive: GamepadButton, _ negative: GamepadButton) -> Float {
          Float((directions.contains(positive) ? 1 : 0) - (directions.contains(negative) ? 1 : 0))
        }
        setStick(gamepad.dpad, axis(.dpadRight, .dpadLeft), axis(.dpadUp, .dpadDown))
      default:
        guard let input = input(for: button), input.value != (pressed ? 1 : 0) else { return }
        input.setValue(pressed ? 1 : 0)
        notify(input)
      }
    }

    @MainActor func setLeftStick(_ value: SIMD2<Float>) {
      setStick(gamepad.leftThumbstick, value.x, value.y)
    }
    @MainActor func setRightStick(_ value: SIMD2<Float>) {
      setStick(gamepad.rightThumbstick, value.x, value.y)
    }

    private func input(for button: GamepadButton) -> GCControllerButtonInput? {
      switch button {
      case .a: gamepad.buttonA
      case .b: gamepad.buttonB
      case .x: gamepad.buttonX
      case .y: gamepad.buttonY
      case .leftShoulder: gamepad.leftShoulder
      case .leftTrigger: gamepad.leftTrigger
      case .rightShoulder: gamepad.rightShoulder
      case .rightTrigger: gamepad.rightTrigger
      case .leftStick: gamepad.leftThumbstickButton
      case .rightStick: gamepad.rightThumbstickButton
      case .view: gamepad.buttonOptions
      case .menu: gamepad.buttonMenu
      case .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .pause: nil
      }
    }

    @MainActor private func setStick(_ pad: GCControllerDirectionPad, _ x: Float, _ y: Float) {
      guard pad.xAxis.value != x || pad.yAxis.value != y else { return }
      pad.setValueForXAxis(x, yAxis: y)
      notify(pad)
    }

    /// Runs the game's handlers for a changed element the way hardware input does: the element,
    /// a pad's axes, its collections, then the gamepad.
    @MainActor private func notify(_ element: GCControllerElement) {
      run(element)
      if let pad = element as? GCControllerDirectionPad {
        run(pad.xAxis)
        run(pad.yAxis)
      }
      var collection = element.collection
      while let parent = collection {
        run(parent)
        collection = parent.collection
      }
      if let handler = handler(for: gamepad) {
        unsafeBitCast(handler, to: GamepadHandler.self)(gamepad, element)
      }
    }

    @MainActor private func run(_ element: GCControllerElement) {
      guard let handler = handler(for: element) else { return }
      switch element {
      case let button as GCControllerButtonInput:
        unsafeBitCast(handler, to: ButtonHandler.self)(button, button.value, button.isPressed)
      case let pad as GCControllerDirectionPad:
        unsafeBitCast(handler, to: PadHandler.self)(pad, pad.xAxis.value, pad.yAxis.value)
      case let axis as GCControllerAxisInput:
        unsafeBitCast(handler, to: AxisHandler.self)(axis, axis.value)
      default: break
      }
    }

    private func handler(for element: AnyObject) -> AnyObject? {
      handlers.withLock { $0.object(forKey: element) }
    }

    // MARK: Presentation to the game

    /// The engine selects its layout from the controller category; it knows Xbox, DualShock 4
    /// and DualSense, so other controllers are presented as Xbox controllers.
    private func presentToGame(
      _ metaclass: AnyClass, controllers: @escaping @convention(c) (AnyObject, Selector) -> NSArray
    ) {
      let controller = controller
      ObjectiveCRuntime.replace(metaclass, #selector(GCController.controllers)) { _ in
        let block: @convention(block) (AnyObject) -> NSArray = { [self] cls in
          let list = controllers(cls, #selector(GCController.controllers))
          return isHardwareConnected ? list : list.adding(controller) as NSArray
        }
        return block
      }
      ObjectiveCRuntime.replace(metaclass, #selector(getter: GCController.current)) { original in
        let current = unsafeBitCast(
          original, to: (@convention(c) (AnyObject, Selector) -> GCController?).self)
        let block: @convention(block) (AnyObject) -> GCController? = { [self] cls in
          current(cls, #selector(getter: GCController.current))
            ?? (isHardwareConnected ? nil : controller)
        }
        return block
      }
      let known: Set<String> = [
        GCProductCategoryXboxOne, GCProductCategoryDualShock4, GCProductCategoryDualSense,
      ]
      ObjectiveCRuntime.replace(GCController.self, #selector(getter: GCController.productCategory))
      { original in
        let category = unsafeBitCast(
          original, to: (@convention(c) (GCController, Selector) -> NSString).self)
        let block: @convention(block) (GCController) -> NSString = { device in
          if device === controller { return GCProductCategoryXboxOne as NSString }
          let reported = category(device, #selector(getter: GCController.productCategory))
          guard !device.isSnapshot, device.extendedGamepad != nil,
            !known.contains(reported as String)
          else {
            return reported
          }
          return GCProductCategoryXboxOne as NSString
        }
        return block
      }
      ObjectiveCRuntime.replace(GCController.self, #selector(getter: GCController.vendorName)) {
        original in
        let vendor = unsafeBitCast(
          original, to: (@convention(c) (GCController, Selector) -> NSString?).self)
        let block: @convention(block) (GCController) -> NSString? = { device in
          device === controller
            ? "Xbox Wireless Controller"
            : vendor(device, #selector(getter: GCController.vendorName))
        }
        return block
      }
    }

    /// Records the handlers the game sets on the virtual elements, and whether it has set any on
    /// hardware.
    private func observeGameHandlers() {
      let selector = Selector(("setValueChangedHandler:"))
      var hooked: Set<ObjectIdentifier> = []
      for sample in [gamepad, gamepad.buttonA, gamepad.dpad, gamepad.dpad.xAxis] as [AnyObject] {
        guard let cls = object_getClass(sample), hooked.insert(ObjectIdentifier(cls)).inserted
        else {
          continue
        }
        ObjectiveCRuntime.replace(cls, selector) { original in
          let set = unsafeBitCast(
            original, to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Void).self)
          let block: @convention(block) (AnyObject, AnyObject?) -> Void = {
            [self] element, handler in
            if elements.contains(ObjectIdentifier(element)) {
              // The game may pass a stack block; keep a copy.
              let copy = (handler as? NSObject)?.copy() as AnyObject?
              handlers.withLock {
                if let copy {
                  $0.setObject(copy, forKey: element)
                } else {
                  $0.removeObject(forKey: element)
                }
              }
            } else if handler != nil {
              hardwareHandled.store(true, ordering: .relaxed)
            }
            set(element, selector, handler)
          }
          return block
        }
      }
    }

    // MARK: Hardware controllers

    @MainActor private func observeHardware() {
      for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) {
          [self] notification in
          guard (notification.object as AnyObject?) !== controller else { return }
          MainThread.async { self.hardwareChanged(connected: name == .GCControllerDidConnect) }
        }
      }
    }

    /// A connection is applied at once and again on the next turn, when the controller list has
    /// it; a disconnection waits briefly in case the controller reconnects.
    @MainActor private func hardwareChanged(connected: Bool) {
      generation += 1
      let current = generation
      if connected {
        updateHardware()
        MainThread.async { self.updateHardware() }
        return
      }
      Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
        MainActor.assumeIsolated {
          if current == self.generation { self.updateHardware() }
        }
      }
    }

    @MainActor private func updateHardware() {
      let connected = !hardware().isEmpty
      guard hardwareConnected.exchange(connected, ordering: .relaxed) != connected else { return }
      directions.removeAll()
      for case let button as GCControllerButtonInput in gamepad.allElements { button.setValue(0) }
      for pad in [gamepad.leftThumbstick, gamepad.rightThumbstick, gamepad.dpad] {
        pad.setValueForXAxis(0, yAxis: 0)
      }
      NotificationCenter.default.post(
        name: connected ? .GCControllerDidDisconnect : .GCControllerDidConnect, object: controller)
      GamepadOverlay.shared?.setControllerConnected(connected)
      RuntimeLog.write(connected ? "hardware controller took over" : "touch gamepad back")
    }

    /// Tells the game about its controller once it is drawing, after its launch callbacks have
    /// registered the observers. A hardware controller connected before launch is announced
    /// unless the game already found it.
    @MainActor func announce() {
      if isHardwareConnected {
        guard !hardwareHandled.load(ordering: .relaxed) else { return }
        for device in hardware() where device.extendedGamepad != nil {
          NotificationCenter.default.post(name: .GCControllerDidConnect, object: device)
        }
      } else {
        NotificationCenter.default.post(name: .GCControllerDidConnect, object: controller)
      }
    }
  }
#endif
