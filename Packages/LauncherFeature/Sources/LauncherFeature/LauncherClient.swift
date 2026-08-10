import InstallationFeature

public struct LauncherClient: Sendable {
  public var isGameReady: @Sendable () -> Bool
  public var play: @MainActor @Sendable (Int) throws -> Void

  public init(
    isGameReady: @escaping @Sendable () -> Bool = { GameInstallationLayout.current.isReady },
    play: @escaping @MainActor @Sendable (Int) throws -> Void
  ) {
    self.isGameReady = isGameReady
    self.play = play
  }
}
