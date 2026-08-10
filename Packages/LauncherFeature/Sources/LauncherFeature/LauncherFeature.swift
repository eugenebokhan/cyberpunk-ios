import ComposableArchitecture
import GamepadFeature

@Reducer
public struct LauncherFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    public var resolutions: [String]
    public var resolution: Int
    public var isGameReady = false
    public var hasCheckedFiles = false
    public var isLaunchingGame = false
    public var isSettingsPresented = false
    public var failure: String?
    public var gamepad = GamepadFeature.State()

    public init(resolutions: [String], resolution: Int) {
      self.resolutions = resolutions
      self.resolution = resolutions.indices.contains(resolution) ? resolution : 0
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case refreshReadiness
    case playTapped
    case launchFailed(String)
    case dismissFailure
    case gamepad(GamepadFeature.Action)
  }

  private let client: LauncherClient

  public init(client: LauncherClient) {
    self.client = client
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Scope(state: \.gamepad, action: \.gamepad) { GamepadFeature() }
    Reduce { state, action in
      switch action {
      case .binding, .gamepad:
        return .none
      case .refreshReadiness:
        let wasGameReady = state.isGameReady
        state.hasCheckedFiles = true
        state.isGameReady = client.isGameReady()
        guard !wasGameReady else { return .none }
        return launch(&state)
      case .playTapped:
        return launch(&state)
      case .launchFailed(let message):
        state.isLaunchingGame = false
        state.failure = message
        return .none
      case .dismissFailure:
        state.failure = nil
        return .none
      }
    }
  }

  private func launch(
    _ state: inout State
  ) -> Effect<Action> {
    guard state.isGameReady, !state.isLaunchingGame,
      state.resolutions.indices.contains(state.resolution)
    else { return .none }
    state.isLaunchingGame = true
    state.failure = nil
    return .run { [resolution = state.resolution] _ in
      try await client.play(resolution)
    } catch: { error, send in
      await send(.launchFailed(error.localizedDescription))
    }
  }
}
