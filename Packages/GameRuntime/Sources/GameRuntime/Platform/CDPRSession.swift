#if os(iOS)
  import Darwin
  import Synchronization

  /// Restores the saved CD PROJEKT RED session through the game's native sign-in. On the Mac the
  /// session comes back from user.gls; here the game reads the profile but does not sign in, so
  /// after the first successful read the runtime loads the stored token into the account service
  /// and hands it to the native user API, once.
  enum CDPRSession {
    /// App Store 2.5.0 (5814786.13589799) executable; every address below belongs to this build.
    private static let supportedExecutable: [UInt8] = [
      0x03, 0x8b, 0x50, 0xeb, 0xa6, 0x7e, 0x37, 0x5a, 0xb0, 0x7b, 0x95, 0xf0, 0xc0, 0x46, 0x35,
      0x30,
    ]
    private static let serviceSlot = 0x1_07fd_2b48
    private static let serviceVTable = 0x1_07c3_4130
    private static let tokenOffset = 0x198
    private static let tokenLength = 0x1_0002_939c
    private static let tokenText = 0x1_0002_9954
    private static let loadToken = 0x1_02b0_84cc

    private static let profileDescriptor = Atomic<Int32>(-1)
    private static let profileLoaded = Atomic(false)
    @MainActor private static var attempted = false
    private static let isSupported = MachOImage.main.uuid == supportedExecutable

    static func didOpen(_ descriptor: Int32, path: UnsafePointer<CChar>) {
      let name =
        strrchr(path, Int32(UInt8(ascii: "/"))).map { $0 + 1 }
        ?? UnsafeMutablePointer(mutating: path)
      if strcmp(name, "user.gls") == 0 { profileDescriptor.store(descriptor, ordering: .relaxed) }
    }

    static func didClose(_ descriptor: Int32, result: Int32) {
      guard descriptor >= 0,
        profileDescriptor.compareExchange(expected: descriptor, desired: -1, ordering: .relaxed)
          .exchanged
      else { return }
      if result == 0 { profileLoaded.store(true, ordering: .releasing) }
    }

    /// Called from the game's event poll on the main thread.
    @MainActor static func restoreIfNeeded() {
      guard profileLoaded.load(ordering: .acquiring), isSupported, !attempted else { return }
      let slide = MachOImage.main.slide
      let service = UnsafePointer<UInt>(bitPattern: slide + serviceSlot)!.pointee
      guard service != 0,
        UnsafePointer<UInt>(bitPattern: service)!.pointee
          == UInt(bitPattern: slide + serviceVTable),
        let userAPI = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_ZN9redgalaxy3api4UserEv"),
        let user = unsafeBitCast(
          userAPI, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)()
      else { return }
      profileLoaded.store(false, ordering: .relaxed)
      typealias Length = @convention(c) (UInt) -> UInt32
      let length = unsafeBitCast(slide + tokenLength, to: Length.self)
      let token = service + UInt(tokenOffset)
      guard length(token) == 0 else { return }
      attempted = true
      unsafeBitCast(slide + loadToken, to: (@convention(c) (UInt) -> Void).self)(service)
      guard length(token) != 0 else { return }
      let text = unsafeBitCast(
        slide + tokenText, to: (@convention(c) (UInt) -> UnsafePointer<CChar>?).self)(token)
      let methods = user.load(as: UnsafePointer<UnsafeRawPointer>.self)
      typealias SignIn =
        @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>?, UnsafeRawPointer?) -> Void
      unsafeBitCast(methods[7], to: SignIn.self)(user, text, nil)
      RuntimeLog.write("CDPR: restoring the saved account through native sign-in")
    }
  }
#endif
