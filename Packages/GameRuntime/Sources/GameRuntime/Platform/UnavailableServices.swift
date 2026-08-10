#if os(iOS)
  import Security

  // macOS services the game probes that iOS apps do not have. Each answers the way the Mac API
  // reports an absent service: no matching objects, an unsupported or unknown-property status.

  private let ioReturnUnsupported = Int32(bitPattern: 0xe000_02c7)
  /// kAudioHardwareUnknownPropertyError, 'who?'.
  private let audioUnknownProperty: Int32 = 0x7768_6f3f

  @_cdecl("IOServiceMatching")
  public func ioServiceMatching(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? { nil }

  @_cdecl("IORegistryEntryIDMatching")
  public func ioRegistryEntryIDMatching(_ identifier: UInt64) -> UnsafeMutableRawPointer? { nil }

  @_cdecl("IOServiceGetMatchingService")
  public func ioServiceGetMatchingService(_ port: UInt32, _ matching: UnsafeMutableRawPointer?)
    -> UInt32
  { 0 }

  @_cdecl("IOServiceGetMatchingServices")
  public func ioServiceGetMatchingServices(
    _ port: UInt32, _ matching: UnsafeMutableRawPointer?, _ iterator: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    iterator?.pointee = 0
    return ioReturnUnsupported
  }

  @_cdecl("IOIteratorNext")
  public func ioIteratorNext(_ iterator: UInt32) -> UInt32 { 0 }

  @_cdecl("IOObjectRelease")
  public func ioObjectRelease(_ object: UInt32) -> Int32 { 0 }

  @_cdecl("IORegistryEntryCreateCFProperty")
  public func ioRegistryEntryCreateCFProperty(
    _ entry: UInt32, _ key: UnsafeRawPointer?, _ allocator: UnsafeRawPointer?, _ options: UInt32
  ) -> UnsafeMutableRawPointer? { nil }

  @_cdecl("IORegistryEntrySearchCFProperty")
  public func ioRegistryEntrySearchCFProperty(
    _ entry: UInt32, _ plane: UnsafePointer<CChar>?, _ key: UnsafeRawPointer?,
    _ allocator: UnsafeRawPointer?, _ options: UInt32
  ) -> UnsafeMutableRawPointer? { nil }

  @_cdecl("IONotificationPortCreate")
  public func ioNotificationPortCreate(_ port: UInt32) -> UnsafeMutableRawPointer? { nil }

  @_cdecl("IONotificationPortDestroy")
  public func ioNotificationPortDestroy(_ notificationPort: UnsafeMutableRawPointer?) {}

  @_cdecl("IONotificationPortSetDispatchQueue")
  public func ioNotificationPortSetDispatchQueue(
    _ notificationPort: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?
  ) {}

  @_cdecl("IOServiceAddInterestNotification")
  public func ioServiceAddInterestNotification(
    _ notificationPort: UnsafeMutableRawPointer?, _ service: UInt32,
    _ interest: UnsafePointer<CChar>?,
    _ callback: UnsafeRawPointer?, _ context: UnsafeMutableRawPointer?,
    _ notification: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    notification?.pointee = 0
    return ioReturnUnsupported
  }

  @_cdecl("IODisplayCreateInfoDictionary")
  public func ioDisplayCreateInfoDictionary(_ display: UInt32, _ options: UInt32)
    -> UnsafeMutableRawPointer?
  { nil }

  @_cdecl("IODisplayGetFloatParameter")
  public func ioDisplayGetFloatParameter(
    _ display: UInt32, _ options: UInt32, _ name: UnsafeRawPointer?,
    _ value: UnsafeMutablePointer<Float>?
  ) -> Int32 {
    value?.pointee = 0
    return ioReturnUnsupported
  }

  @_cdecl("AudioObjectGetPropertyData")
  public func audioObjectGetPropertyData(
    _ object: UInt32, _ address: UnsafeRawPointer?, _ qualifierSize: UInt32,
    _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>?,
    _ data: UnsafeMutableRawPointer?
  ) -> Int32 { audioUnknownProperty }

  @_cdecl("AudioObjectGetPropertyDataSize")
  public func audioObjectGetPropertyDataSize(
    _ object: UInt32, _ address: UnsafeRawPointer?, _ qualifierSize: UInt32,
    _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    size?.pointee = 0
    return audioUnknownProperty
  }

  @_cdecl("AudioObjectSetPropertyData")
  public func audioObjectSetPropertyData(
    _ object: UInt32, _ address: UnsafeRawPointer?, _ qualifierSize: UInt32,
    _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ data: UnsafeRawPointer?
  ) -> Int32 { audioUnknownProperty }

  @_cdecl("SecItemImport")
  public func secItemImport(
    _ data: UnsafeRawPointer?, _ fileName: UnsafeRawPointer?, _ format: UnsafeMutableRawPointer?,
    _ type: UnsafeMutableRawPointer?, _ flags: UInt32, _ parameters: UnsafeRawPointer?,
    _ keychain: UnsafeMutableRawPointer?, _ items: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> OSStatus {
    items?.pointee = nil
    return errSecUnimplemented
  }

  @_cdecl("SecItemExport")
  public func secItemExport(
    _ item: UnsafeRawPointer?, _ format: UInt32, _ flags: UInt32, _ parameters: UnsafeRawPointer?,
    _ data: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> OSStatus {
    data?.pointee = nil
    return errSecUnimplemented
  }

  @_cdecl("SecIdentityCreateWithCertificate")
  public func secIdentityCreateWithCertificate(
    _ keychains: UnsafeRawPointer?, _ certificate: UnsafeRawPointer?,
    _ identity: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> OSStatus {
    identity?.pointee = nil
    return errSecUnimplemented
  }

  /// The Mac long description of a certificate; iOS offers its subject summary.
  @_cdecl("SecCertificateCopyLongDescription")
  public func secCertificateCopyLongDescription(
    _ allocator: UnsafeRawPointer?, _ certificate: UnsafeRawPointer,
    _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> UnsafeMutableRawPointer? {
    error?.pointee = nil
    let certificate = Unmanaged<SecCertificate>.fromOpaque(certificate).takeUnretainedValue()
    return SecCertificateCopySubjectSummary(certificate).map {
      Unmanaged.passRetained($0).toOpaque()
    }
  }
#endif
