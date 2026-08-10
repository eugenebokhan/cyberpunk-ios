#if os(iOS)
  import ComposableArchitecture
  import GamepadFeature
  import UIKit

  /// The touch gamepad over the game, writing to the virtual controller.
  @MainActor
  final class GamepadOverlay {
    static private(set) var shared: GamepadOverlay?

    private let store: StoreOf<GamepadFeature>
    private let window: PassthroughWindow

    private init(store: StoreOf<GamepadFeature>, window: PassthroughWindow) {
      self.store = store
      self.window = window
    }

    static func install(in scene: UIWindowScene, controller: VirtualController) {
      let store = Store(
        initialState: GamepadFeature.State(
          isGameplay: Gameplay.isActive, controllerConnected: controller.isHardwareConnected)
      ) { GamepadFeature() }
      let client = GamepadInputClient(
        sendButton: { controller.set($0, pressed: $1) },
        sendLeftStick: { controller.setLeftStick($0) },
        sendRightStick: { controller.setRightStick($0) })
      let window = PassthroughWindow(windowScene: scene)
      window.windowLevel = .normal + 1
      window.backgroundColor = .clear
      window.rootViewController = makeGamepadViewController(store: store, client: client)
      window.isHidden = true
      shared = GamepadOverlay(store: store, window: window)
    }

    func show() { window.isHidden = false }
    func setGameplay(_ isGameplay: Bool) { store.send(.gameplayChanged(isGameplay)) }
    func setControllerConnected(_ connected: Bool) {
      store.send(.controllerConnectionChanged(connected))
    }
  }

  /// A window over the game that keeps only the touches on its own controls.
  final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      let view = super.hitTest(point, with: event)
      return view === self || view === rootViewController?.view ? nil : view
    }
  }
#endif
