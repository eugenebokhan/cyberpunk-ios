@MainActor
public struct GamepadInputClient {
  public let sendButton: (GamepadButton, Bool) -> Void
  public let sendLeftStick: (SIMD2<Float>) -> Void
  public let sendRightStick: (SIMD2<Float>) -> Void

  public init(
    sendButton: @escaping (GamepadButton, Bool) -> Void,
    sendLeftStick: @escaping (SIMD2<Float>) -> Void,
    sendRightStick: @escaping (SIMD2<Float>) -> Void
  ) {
    self.sendButton = sendButton
    self.sendLeftStick = sendLeftStick
    self.sendRightStick = sendRightStick
  }
}
