#if canImport(SwiftUI)
  import ComposableArchitecture
  import SwiftUI

  @MainActor
  public func gamepadSettings(store: StoreOf<GamepadFeature>) -> some View {
    GamepadSettings(store: store)
  }

  private struct GamepadSettings: View {
    let store: StoreOf<GamepadFeature>

    var body: some View {
      LabeledContent(
        "Look Sensitivity", value: store.lookSensitivity,
        format: .number.precision(.fractionLength(1)))
      Slider(
        value: Binding(
          get: { store.lookSensitivity }, set: { store.send(.lookSensitivityChanged($0)) }),
        in: 0.25...4, step: 0.05
      )
      .accessibilityLabel("Look Sensitivity")
    }
  }
#endif
