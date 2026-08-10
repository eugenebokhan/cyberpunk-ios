#if os(iOS)
  import Foundation

  /// Called once by the library constructor, before the game's own initializers run.
  @_cdecl("GameRuntimeLoad")
  public func gameRuntimeLoad() {
    RuntimeLog.open()
    BackgroundSuspension.install()
    MetalCompatibility.install()
    MemoryBudget.install()
    AppKitDrawing.install()
  }
#endif
