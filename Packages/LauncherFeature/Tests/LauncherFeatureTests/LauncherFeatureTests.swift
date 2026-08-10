import ComposableArchitecture
import Foundation
import Testing

@testable import LauncherFeature

@MainActor
struct LauncherFeatureTests {
  @Test func missingDataBlocksStartup() async {
    let launches = LockIsolated(0)
    let store = makeStore(
      client: LauncherClient(
        isGameReady: { false }, play: { _ in launches.withValue { $0 += 1 } }))
    await store.send(.refreshReadiness) { $0.hasCheckedFiles = true }
    await store.send(.playTapped)
    #expect(launches.value == 0)
  }

  @Test func readyDataStartsGameOnceWithoutLauncherOnboarding() async {
    let resolutions = LockIsolated<[Int]>([])
    let store = makeStore(
      client: LauncherClient(
        isGameReady: { true },
        play: { resolution in resolutions.withValue { $0.append(resolution) } }))
    await store.send(.refreshReadiness) {
      $0.hasCheckedFiles = true
      $0.isGameReady = true
      $0.isLaunchingGame = true
    }
    await store.finish()
    await store.send(.refreshReadiness)
    await store.send(.playTapped)
    #expect(resolutions.value == [1])
  }

  @Test func failedStartupRequiresExplicitRetry() async {
    let error = CocoaError(.featureUnsupported)
    let launches = LockIsolated(0)
    let store = makeStore(
      client: LauncherClient(
        isGameReady: { true },
        play: { _ in
          launches.withValue { $0 += 1 }
          throw error
        }))
    await store.send(.refreshReadiness) {
      $0.hasCheckedFiles = true
      $0.isGameReady = true
      $0.isLaunchingGame = true
    }
    await store.receive(\.launchFailed) {
      $0.isLaunchingGame = false
      $0.failure = error.localizedDescription
    }
    await store.send(.refreshReadiness)
    #expect(launches.value == 1)
    await store.send(.playTapped) {
      $0.isLaunchingGame = true
      $0.failure = nil
    }
    await store.receive(\.launchFailed) {
      $0.isLaunchingGame = false
      $0.failure = error.localizedDescription
    }
    #expect(launches.value == 2)
  }

  @Test func completedTransferStartsWaitingGame() async {
    let ready = LockIsolated(false)
    let launches = LockIsolated(0)
    let store = makeStore(
      client: LauncherClient(
        isGameReady: { ready.value }, play: { _ in launches.withValue { $0 += 1 } }))
    await store.send(.refreshReadiness) { $0.hasCheckedFiles = true }
    ready.setValue(true)
    await store.send(.refreshReadiness) {
      $0.isGameReady = true
      $0.isLaunchingGame = true
    }
    await store.finish()
    #expect(launches.value == 1)
  }

  private func makeStore(client: LauncherClient) -> TestStoreOf<LauncherFeature> {
    let state = withDependencies {
      $0.defaultAppStorage = .inMemory
    } operation: {
      LauncherFeature.State(resolutions: ["A", "B"], resolution: 1)
    }
    return TestStore(initialState: state) { LauncherFeature(client: client) }
  }
}
