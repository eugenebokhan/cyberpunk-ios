import GamepadFeature

struct ControllerInputBuffer {
  enum Event: Equatable {
    case button(GamepadButton, Bool)
    case leftStick(SIMD2<Float>)
    case rightStick(SIMD2<Float>)
  }

  private var buttons: [Event] = []
  private var pressed: Set<GamepadButton> = []
  private var left = SIMD2<Float>.zero
  private var right = SIMD2<Float>.zero
  private var pendingLeft: SIMD2<Float>?
  private var pendingRight: SIMD2<Float>?

  mutating func append(_ event: Event) {
    switch event {
    case .button(let button, let down):
      guard pressed.contains(button) != down else { return }
      if down { pressed.insert(button) } else { pressed.remove(button) }
      buttons.append(event)
    case .leftStick(let value):
      let value = Self.normalized(value)
      guard value != left else { return }
      left = value
      pendingLeft = value
    case .rightStick(let value):
      let value = Self.normalized(value)
      guard value != right else { return }
      right = value
      pendingRight = value
    }
  }

  mutating func drain() -> [Event] {
    var result = buttons
    if let pendingLeft { result.append(.leftStick(pendingLeft)) }
    if let pendingRight { result.append(.rightStick(pendingRight)) }
    buttons.removeAll(keepingCapacity: true)
    pendingLeft = nil
    pendingRight = nil
    return result
  }

  mutating func clear() { self = Self() }

  private static func normalized(_ value: SIMD2<Float>) -> SIMD2<Float> {
    SIMD2(
      value.x.isFinite ? min(max(value.x, -1), 1) : 0,
      value.y.isFinite ? min(max(value.y, -1), 1) : 0)
  }
}

#if os(iOS)
  import GameController
  import UIKit

  @MainActor
  final class VirtualController {
    private(set) static var shared: VirtualController?
    private let native: GCVirtualController
    private let inputQueue = DispatchQueue(
      label: "GameRuntime.controller-input", qos: .userInteractive)
    private var controller: GCController?
    private var observers: [NSObjectProtocol] = []
    private var connecting = false
    private var connected = false
    private var flushScheduled = false
    private var pending = ControllerInputBuffer()
    private var directions: Set<GamepadButton> = []
    private var escapeDown = false

    private static let elements: [GamepadButton: String] = [
      .a: GCInputButtonA, .b: GCInputButtonB, .x: GCInputButtonX, .y: GCInputButtonY,
      .leftShoulder: GCInputLeftShoulder, .rightShoulder: GCInputRightShoulder,
      .leftTrigger: GCInputLeftTrigger, .rightTrigger: GCInputRightTrigger,
      .leftStick: GCInputLeftThumbstickButton, .rightStick: GCInputRightThumbstickButton,
      .view: GCInputButtonOptions, .menu: GCInputButtonMenu,
    ]

    private static let normalizeCategory: Void = {
      let selector = #selector(getter: GCController.productCategory)
      let known: Set<String> = [
        GCProductCategoryXboxOne, GCProductCategoryDualShock4, GCProductCategoryDualSense,
      ]
      ObjectiveCRuntime.replace(GCController.self, selector) { original in
        let category = unsafeBitCast(
          original, to: (@convention(c) (GCController, Selector) -> NSString).self)
        let block: @convention(block) (GCController) -> NSString = { device in
          let value = category(device, selector)
          return device.extendedGamepad != nil && !device.isSnapshot
            && !known.contains(value as String)
            ? GCProductCategoryXboxOne as NSString : value
        }
        return block
      }
    }()

    private init() {
      let configuration = GCVirtualController.Configuration()
      configuration.isHidden = true
      configuration.elements = Set(Self.elements.values).union([
        GCInputDirectionPad, GCInputLeftThumbstick, GCInputRightThumbstick,
      ])
      native = GCVirtualController(configuration: configuration)
    }

    deinit {
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    static func install() async throws -> VirtualController {
      if let shared { return shared }
      _ = normalizeCategory
      let instance = VirtualController()
      instance.observeConnections()
      try await instance.updateConnection()
      shared = instance
      return instance
    }

    private var hardware: [GCController] {
      GCController.controllers().filter {
        $0 !== controller && !$0.isSnapshot && $0.extendedGamepad != nil
      }
    }

    var isHardwareConnected: Bool { !hardware.isEmpty }

    func set(_ button: GamepadButton, pressed: Bool) { enqueue(.button(button, pressed)) }
    func setLeftStick(_ value: SIMD2<Float>) { enqueue(.leftStick(value)) }
    func setRightStick(_ value: SIMD2<Float>) { enqueue(.rightStick(value)) }

    private func enqueue(_ event: ControllerInputBuffer.Event) {
      guard connected, !isHardwareConnected else { return }
      pending.append(event)
      guard !flushScheduled else { return }
      flushScheduled = true
      MainThread.async { [weak self] in self?.flush() }
    }

    private func flush() {
      flushScheduled = false
      let events = pending.drain()
      guard connected, !isHardwareConnected else { return }
      for event in events {
        switch event {
        case .leftStick(let value):
          native.setPosition(
            CGPoint(x: CGFloat(value.x), y: CGFloat(value.y)),
            forDirectionPadElement: GCInputLeftThumbstick)
        case .rightStick(let value):
          native.setPosition(
            CGPoint(x: CGFloat(value.x), y: CGFloat(value.y)),
            forDirectionPadElement: GCInputRightThumbstick)
        case .button(let button, let pressed):
          if button == .pause {
            escapeDown = pressed
            NSApplication.shared.post(
              NSEvent.key(53, characters: "\u{1b}", pressed: pressed), atStart: false)
          } else if [.dpadUp, .dpadDown, .dpadLeft, .dpadRight].contains(button) {
            if pressed { directions.insert(button) } else { directions.remove(button) }
            let x =
              (directions.contains(.dpadRight) ? 1 : 0) - (directions.contains(.dpadLeft) ? 1 : 0)
            let y =
              (directions.contains(.dpadUp) ? 1 : 0) - (directions.contains(.dpadDown) ? 1 : 0)
            native.setPosition(CGPoint(x: x, y: y), forDirectionPadElement: GCInputDirectionPad)
          } else if let element = Self.elements[button] {
            native.setValue(pressed ? 1 : 0, forButtonElement: element)
          }
        }
      }
    }

    private func reset() {
      if escapeDown {
        escapeDown = false
        NSApplication.shared.post(
          NSEvent.key(53, characters: "\u{1b}", pressed: false), atStart: false)
      }
      pending.clear()
      directions.removeAll()
      if connected {
        for element in Self.elements.values { native.setValue(0, forButtonElement: element) }
        for element in [GCInputDirectionPad, GCInputLeftThumbstick, GCInputRightThumbstick] {
          native.setPosition(.zero, forDirectionPadElement: element)
        }
      }
    }

    private func updateConnection() async throws {
      guard !connecting else { return }
      if isHardwareConnected {
        reset()
        native.disconnect()
        connected = false
        GamepadOverlay.shared?.setControllerConnected(true)
        return
      }
      guard !connected else { return }
      connecting = true
      GamepadOverlay.shared?.setControllerConnected(true)
      defer { connecting = false }
      try await native.connect()
      guard let device = native.controller, device.extendedGamepad != nil else {
        native.disconnect()
        throw NSError(
          domain: "GameRuntime.Controller", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: "iOS did not provide the configured virtual controller."
          ])
      }
      controller = device
      device.handlerQueue = inputQueue
      device.playerIndex = .index1
      connected = true
      if isHardwareConnected {
        reset()
        native.disconnect()
        connected = false
      }
      GamepadOverlay.shared?.setControllerConnected(isHardwareConnected)
    }

    private func observeConnections() {
      for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
        observers.append(
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] notification in
            MainThread.async {
              guard let self, !self.connecting,
                (notification.object as? GCController) !== self.controller
              else { return }
              Task { @MainActor in
                do { try await self.updateConnection() } catch {
                  GameApplicationDelegate.presentRuntimeError(error)
                }
              }
            }
          })
      }
      observers.append(
        NotificationCenter.default.addObserver(
          forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainThread.async { self?.reset() }
        })
    }

    func announce() {
      let devices = isHardwareConnected ? hardware : controller.map { [$0] } ?? []
      for device in devices {
        NotificationCenter.default.post(name: .GCControllerDidConnect, object: device)
        if device === controller { device.handlerQueue = inputQueue }
      }
    }
  }
#endif
