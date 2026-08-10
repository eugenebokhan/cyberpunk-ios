import Foundation

struct GamepadTouchState {
  enum Control: Hashable {
    case leftStick, rightStick
    case button(GamepadButton)
  }

  private var touches: [ObjectIdentifier: Control] = [:]
  private(set) var leftStick = SIMD2<Float>.zero
  private(set) var rightStick = SIMD2<Float>.zero
  private(set) var buttons: Set<GamepadButton> = []

  var leftStickHeld: Bool { touches.values.contains(.leftStick) }
  var rightStickHeld: Bool { touches.values.contains(.rightStick) }

  func control(for touch: ObjectIdentifier) -> Control? { touches[touch] }

  mutating func begin(_ touch: ObjectIdentifier, on control: Control) -> Bool {
    guard touches[touch] == nil, !touches.values.contains(control) else { return false }
    touches[touch] = control
    if case .button(let button) = control { buttons.insert(button) }
    return true
  }

  mutating func move(_ touch: ObjectIdentifier, displacement: SIMD2<Float>, radius: Float) {
    guard radius > 0, displacement.x.isFinite, displacement.y.isFinite else { return }
    let length = (displacement.x * displacement.x + displacement.y * displacement.y).squareRoot()
    let strength = max(0, (min(length / radius, 1) - 0.12) / 0.88)
    let value = length > 0 ? displacement * (strength / length) : .zero
    switch touches[touch] {
    case .leftStick: leftStick = value
    case .rightStick: rightStick = value
    default: break
    }
  }

  func rightStick(sensitivity: Float) -> SIMD2<Float> {
    let value = rightStick * (min(4, max(0.25, sensitivity)) / 1.5)
    let length = (value.x * value.x + value.y * value.y).squareRoot()
    return length > 1 ? value / length : value
  }

  mutating func end(_ touch: ObjectIdentifier) {
    switch touches.removeValue(forKey: touch) {
    case .leftStick: leftStick = .zero
    case .rightStick: rightStick = .zero
    case .button(let button): buttons.remove(button)
    case nil: break
    }
  }

  mutating func reset() {
    touches.removeAll(keepingCapacity: true)
    buttons.removeAll(keepingCapacity: true)
    leftStick = .zero
    rightStick = .zero
  }
}
