public enum GamepadButton: Int, CaseIterable, Hashable, Sendable {
  case a, b, x, y
  case leftShoulder, leftTrigger, rightShoulder, rightTrigger
  case leftStick, rightStick
  case dpadUp, dpadDown, dpadLeft, dpadRight
  case view, menu, pause
}
