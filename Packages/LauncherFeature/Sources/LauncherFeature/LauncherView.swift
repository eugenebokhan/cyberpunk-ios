#if canImport(UIKit)
  import ComposableArchitecture
  import GamepadFeature
  import SwiftUI
  import UIKit

  public struct LauncherView: View {
    @Bindable public var store: StoreOf<LauncherFeature>
    private let icon: UIImage
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(store: StoreOf<LauncherFeature>, icon: UIImage) {
      self.store = store
      self.icon = icon
    }

    public var body: some View {
      let layout =
        verticalSizeClass == .compact
        ? AnyLayout(HStackLayout(spacing: 48))
        : AnyLayout(VStackLayout(spacing: 32))
      ScrollView {
        layout {
          VStack(spacing: 16) {
            Image(uiImage: icon).resizable().scaledToFit().frame(width: 112, height: 112)
              .clipShape(.rect(cornerRadius: 24))
            if !store.hasCheckedFiles || store.isLaunchingGame {
              ProgressView().tint(.red).controlSize(.large)
            } else if !store.isGameReady {
              Text(
                "Connect this iPhone to the Mac with Cyberpunk 2077 installed, then install this app from Xcode to copy the game data."
              )
              .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
          }
          .frame(maxWidth: .infinity)
          VStack(spacing: 12) {
            if store.hasCheckedFiles && !store.isLaunchingGame {
              Button {
                store.send(store.isGameReady ? .playTapped : .refreshReadiness)
              } label: {
                Text(store.isGameReady ? "Try again" : "Check again")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .controlSize(.large)
          .frame(maxWidth: 360)
        }
        .padding(32)
      }
      .defaultScrollAnchor(.center, for: .alignment)
      .scrollBounceBehavior(.basedOnSize)
      .overlay(alignment: .topTrailing) {
        Button {
          store.send(.binding(.set(\.isSettingsPresented, true)))
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.white)
        .disabled(store.isLaunchingGame)
        .padding()
      }
      .background(.black)
      .tint(.red)
      .preferredColorScheme(.dark)
      .statusBarHidden()
      .persistentSystemOverlays(.hidden)
      .onAppear { store.send(.refreshReadiness) }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      ) { _ in
        store.send(.refreshReadiness)
      }
      .sheet(isPresented: $store.isSettingsPresented) { settings }
      .alert(
        "Can't Start",
        isPresented: Binding(
          get: { store.failure != nil },
          set: { if !$0 { store.send(.dismissFailure) } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(store.failure ?? "")
      }
    }

    private var settings: some View {
      NavigationStack {
        Form {
          Picker("Resolution", selection: $store.resolution) {
            ForEach(Array(store.resolutions.enumerated()), id: \.offset) { index, name in
              Text(name).tag(index)
            }
          }
          gamepadSettings(store: store.scope(state: \.gamepad, action: \.gamepad))
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { store.send(.binding(.set(\.isSettingsPresented, false))) }
          }
        }
      }
    }
  }
#endif
