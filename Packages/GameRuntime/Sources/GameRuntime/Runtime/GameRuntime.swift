#if os(iOS)
  private let runtimeInstallation: Void = {
    RuntimeLog.open()
    BackgroundSuspension.install()
    MetalCompatibility.install()
    MemoryBudget.install()
    AppKitDrawing.install()
  }()

  /// The constructor may call this repeatedly; Swift completes installation once.
  @_cdecl("GameRuntimeLoad")
  public func gameRuntimeLoad() {
    _ = runtimeInstallation
  }
#endif
