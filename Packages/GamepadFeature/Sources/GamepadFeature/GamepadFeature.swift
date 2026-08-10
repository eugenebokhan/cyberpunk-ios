import ComposableArchitecture

@Reducer
public struct GamepadFeature {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var isGameplay: Bool
    public var controllerConnected: Bool
    public var controlsHidden: Bool
    public var isActive = true
    @Shared(.appStorage("CyPortLookSensitivity")) public var lookSensitivity = 1.5

    public init(
      isGameplay: Bool = false,
      controllerConnected: Bool = false,
      controlsHidden: Bool = false
    ) {
      self.isGameplay = isGameplay
      self.controllerConnected = controllerConnected
      self.controlsHidden = controlsHidden
    }
  }

  public enum Action: Equatable, Sendable {
    case gameplayChanged(Bool)
    case controllerConnectionChanged(Bool)
    case toggleControls
    case lookSensitivityChanged(Double)
    case activate
    case deactivate
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .gameplayChanged(let value): state.isGameplay = value
      case .controllerConnectionChanged(let value): state.controllerConnected = value
      case .toggleControls: state.controlsHidden.toggle()
      case .lookSensitivityChanged(let value):
        guard value.isFinite else { return .none }
        state.$lookSensitivity.withLock { $0 = min(4, max(0.25, value)) }
      case .activate: state.isActive = true
      case .deactivate: state.isActive = false
      }
      return .none
    }
  }
}
