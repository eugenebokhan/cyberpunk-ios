#if os(iOS)
  import CoreGraphics
  import Foundation

  // The Mac display API the engine sizes its output with. The phone screen is display 1, a
  // built-in Apple panel whose only mode is the render mode chosen in the launcher.

  /// Distinct addresses standing in for CGDisplayModeRef values; they live as long as the process.
  private let displayModes = UnsafeMutablePointer<UInt8>.allocate(
    capacity: DisplayMode.scales.count)

  private func displayMode(_ reference: UnsafeRawPointer?) -> DisplayMode {
    guard let reference else { return .selected }
    let index = UnsafeRawPointer(displayModes).distance(to: reference)
    return DisplayMode.scales.indices.contains(index) ? DisplayMode(index: index) : .selected
  }

  private func reference(_ mode: DisplayMode) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(displayModes + mode.index)
  }

  private func pixelSize(_ mode: DisplayMode) -> (width: Int, height: Int) {
    mode.pixelSize(screen: ScreenMetrics.current.size)
  }

  @_cdecl("CGMainDisplayID")
  public func cgMainDisplayID() -> UInt32 { 1 }

  @_cdecl("CGGetActiveDisplayList")
  public func cgGetActiveDisplayList(
    _ capacity: UInt32, _ displays: UnsafeMutablePointer<UInt32>?,
    _ count: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    if let displays, capacity > 0 { displays[0] = 1 }
    count?.pointee = 1
    return 0
  }

  @_cdecl("CGDisplayBounds")
  public func cgDisplayBounds(_ display: UInt32) -> CGRect {
    CGRect(origin: .zero, size: ScreenMetrics.appKitSize)
  }

  @_cdecl("CGDisplayPixelsWide")
  public func cgDisplayPixelsWide(_ display: UInt32) -> Int { pixelSize(.selected).width }

  @_cdecl("CGDisplayPixelsHigh")
  public func cgDisplayPixelsHigh(_ display: UInt32) -> Int { pixelSize(.selected).height }

  @_cdecl("CGDisplayIsBuiltin")
  public func cgDisplayIsBuiltin(_ display: UInt32) -> UInt32 { 1 }

  @_cdecl("CGDisplayIsInMirrorSet")
  public func cgDisplayIsInMirrorSet(_ display: UInt32) -> UInt32 { 0 }

  @_cdecl("CGDisplayVendorNumber")
  public func cgDisplayVendorNumber(_ display: UInt32) -> UInt32 { 0x0610 }

  @_cdecl("CGDisplayModelNumber")
  public func cgDisplayModelNumber(_ display: UInt32) -> UInt32 { 0 }

  @_cdecl("CGDisplaySerialNumber")
  public func cgDisplaySerialNumber(_ display: UInt32) -> UInt32 { 0 }

  @_cdecl("CGDisplayIOServicePort")
  public func cgDisplayIOServicePort(_ display: UInt32) -> UInt32 { 0 }

  @_cdecl("CGDisplayCopyDisplayMode")
  public func cgDisplayCopyDisplayMode(_ display: UInt32) -> UnsafeMutableRawPointer {
    reference(.selected)
  }

  @_cdecl("CGDisplayCopyAllDisplayModes")
  public func cgDisplayCopyAllDisplayModes(_ display: UInt32, _ options: UnsafeRawPointer?)
    -> UnsafeMutableRawPointer
  {
    var modes: [UnsafeRawPointer?] = [UnsafeRawPointer(reference(.selected))]
    return Unmanaged.passRetained(CFArrayCreate(nil, &modes, modes.count, nil)!).toOpaque()
  }

  /// Display modes are process-lifetime constants.
  @_cdecl("CGDisplayModeRelease")
  public func cgDisplayModeRelease(_ mode: UnsafeRawPointer?) {}

  @_cdecl("CGDisplayModeGetWidth")
  public func cgDisplayModeGetWidth(_ mode: UnsafeRawPointer?) -> Int {
    pixelSize(displayMode(mode)).width
  }

  @_cdecl("CGDisplayModeGetHeight")
  public func cgDisplayModeGetHeight(_ mode: UnsafeRawPointer?) -> Int {
    pixelSize(displayMode(mode)).height
  }

  @_cdecl("CGDisplayModeGetPixelWidth")
  public func cgDisplayModeGetPixelWidth(_ mode: UnsafeRawPointer?) -> Int {
    pixelSize(displayMode(mode)).width
  }

  @_cdecl("CGDisplayModeGetPixelHeight")
  public func cgDisplayModeGetPixelHeight(_ mode: UnsafeRawPointer?) -> Int {
    pixelSize(displayMode(mode)).height
  }

  @_cdecl("CGDisplayModeGetRefreshRate")
  public func cgDisplayModeGetRefreshRate(_ mode: UnsafeRawPointer?) -> Double {
    Double(ScreenMetrics.current.framesPerSecond)
  }

  /// kDisplayModeValidFlag | kDisplayModeSafeFlag, plus kDisplayModeNativeFlag for the current mode.
  @_cdecl("CGDisplayModeGetIOFlags")
  public func cgDisplayModeGetIOFlags(_ mode: UnsafeRawPointer?) -> UInt32 {
    displayMode(mode) == .selected ? 0x0200_0003 : 0x0000_0003
  }

  @_cdecl("CGDisplayModeIsUsableForDesktopGUI")
  public func cgDisplayModeIsUsableForDesktopGUI(_ mode: UnsafeRawPointer?) -> UInt32 { 1 }

  /// Detaching the mouse from the cursor is how the game enters gameplay; iOS locks the pointer.
  @_cdecl("CGAssociateMouseAndMouseCursorPosition")
  public func cgAssociateMouseAndMouseCursorPosition(_ connected: UInt32) -> Int32 {
    Gameplay.setPointerLocked(connected == 0)
    return 0
  }

  /// iOS cannot move the system pointer; the AppKit cursor position the game reads follows.
  @_cdecl("CGWarpMouseCursorPosition")
  public func cgWarpMouseCursorPosition(_ point: CGPoint) -> Int32 {
    let size = ScreenMetrics.appKitSize
    NSEvent.cursorLocation = CGPoint(
      x: min(max(point.x, 0), size.width), y: min(max(size.height - point.y, 0), size.height))
    return 0
  }

  @_cdecl("CGEventSourceCreate")
  public func cgEventSourceCreate(_ state: Int32) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained("CyberpunkEventSource" as CFString).toOpaque()
  }

  /// iOS delivers no synthetic Mac events, so there is nothing to suppress.
  @_cdecl("CGEventSourceSetLocalEventsSuppressionInterval")
  public func cgEventSourceSetLocalEventsSuppressionInterval(
    _ source: UnsafeRawPointer?, _ seconds: Double
  ) {}
#endif
