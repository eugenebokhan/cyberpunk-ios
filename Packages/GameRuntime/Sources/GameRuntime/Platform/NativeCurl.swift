#if os(iOS)
  import Foundation

  /// The game links the Mac system libcurl, which iOS does not have. libREDGalaxy64 carries its
  /// own libcurl (TLS against the system trust store, set up by the build tools); its functions
  /// are local symbols, found in the symbol table of the supported library build.
  enum NativeCurl {
    private static let library = "libREDGalaxy64.dylib"
    private static let supportedLibrary: [UInt8] = [
      0x8c, 0x7a, 0x3a, 0xa6, 0xde, 0x6c, 0x3d, 0xf0, 0x8a, 0xfb, 0x8a, 0x7f, 0x4a, 0x82, 0x8c,
      0x90,
    ]
    static let names: Set<String> = [
      "curl_global_init_mem", "curl_global_cleanup", "curl_easy_init", "curl_easy_cleanup",
      "Curl_vsetopt", "curl_easy_getinfo", "curl_easy_perform", "curl_easy_strerror",
      "curl_slist_append", "curl_slist_free_all", "curl_multi_init", "curl_multi_cleanup",
      "curl_multi_add_handle", "curl_multi_remove_handle", "curl_multi_perform",
      "curl_multi_info_read",
    ]

    static let functions: [String: UnsafeRawPointer] = {
      guard let image = MachOImage.loaded(named: library) else {
        unavailable("\(library) is not loaded")
      }
      guard image.uuid == supportedLibrary else { unavailable("unsupported \(library)") }
      let symbols = image.codeSymbols(named: names)
      return Dictionary(
        uniqueKeysWithValues: names.map { name in
          guard let addresses = symbols[name] else { unavailable("missing \(name)") }
          guard addresses.count == 1 else { unavailable("ambiguous \(name)") }
          return (name, addresses[0])
        })
    }()

    static func function<Function>(_ name: String, as _: Function.Type) -> Function {
      unsafeBitCast(functions[name]!, to: Function.self)
    }

    private static func unavailable(_ reason: String) -> Never {
      RuntimeLog.write("native libcurl unavailable: \(reason)")
      fatalError("native libcurl unavailable: \(reason)")
    }
  }

  @_cdecl("GameRuntimeCurlFunction")
  public func gameRuntimeCurlFunction(_ name: UnsafePointer<CChar>) -> UnsafeRawPointer {
    let name = String(cString: name)
    guard let function = NativeCurl.functions[name] else {
      fatalError("unknown curl function \(name)")
    }
    return function
  }

  @_cdecl("curl_global_init_mem")
  public func curlGlobalInitMem(
    _ flags: Int, _ malloc: OpaquePointer?, _ free: OpaquePointer?, _ realloc: OpaquePointer?,
    _ strdup: OpaquePointer?, _ calloc: OpaquePointer?
  ) -> Int32 {
    typealias Function =
      @convention(c) (
        Int, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?
      ) -> Int32
    return NativeCurl.function("curl_global_init_mem", as: Function.self)(
      flags, malloc, free, realloc, strdup, calloc)
  }

  @_cdecl("curl_global_cleanup")
  public func curlGlobalCleanup() {
    NativeCurl.function("curl_global_cleanup", as: (@convention(c) () -> Void).self)()
  }

  @_cdecl("curl_easy_init")
  public func curlEasyInit() -> OpaquePointer? {
    NativeCurl.function("curl_easy_init", as: (@convention(c) () -> OpaquePointer?).self)()
  }

  @_cdecl("curl_easy_cleanup")
  public func curlEasyCleanup(_ handle: OpaquePointer?) {
    NativeCurl.function("curl_easy_cleanup", as: (@convention(c) (OpaquePointer?) -> Void).self)(
      handle)
  }

  @_cdecl("curl_easy_perform")
  public func curlEasyPerform(_ handle: OpaquePointer?) -> Int32 {
    NativeCurl.function("curl_easy_perform", as: (@convention(c) (OpaquePointer?) -> Int32).self)(
      handle)
  }

  @_cdecl("curl_easy_strerror")
  public func curlEasyStrError(_ code: Int32) -> UnsafePointer<CChar>? {
    NativeCurl.function(
      "curl_easy_strerror", as: (@convention(c) (Int32) -> UnsafePointer<CChar>?).self)(code)
  }

  @_cdecl("curl_slist_append")
  public func curlSListAppend(_ list: OpaquePointer?, _ text: UnsafePointer<CChar>?)
    -> OpaquePointer?
  {
    NativeCurl.function(
      "curl_slist_append",
      as: (@convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?).self)(
        list, text)
  }

  @_cdecl("curl_slist_free_all")
  public func curlSListFreeAll(_ list: OpaquePointer?) {
    NativeCurl.function("curl_slist_free_all", as: (@convention(c) (OpaquePointer?) -> Void).self)(
      list)
  }

  @_cdecl("curl_multi_init")
  public func curlMultiInit() -> OpaquePointer? {
    NativeCurl.function("curl_multi_init", as: (@convention(c) () -> OpaquePointer?).self)()
  }

  @_cdecl("curl_multi_cleanup")
  public func curlMultiCleanup(_ multi: OpaquePointer?) -> Int32 {
    NativeCurl.function("curl_multi_cleanup", as: (@convention(c) (OpaquePointer?) -> Int32).self)(
      multi)
  }

  @_cdecl("curl_multi_add_handle")
  public func curlMultiAddHandle(_ multi: OpaquePointer?, _ handle: OpaquePointer?) -> Int32 {
    NativeCurl.function(
      "curl_multi_add_handle", as: (@convention(c) (OpaquePointer?, OpaquePointer?) -> Int32).self)(
        multi, handle)
  }

  @_cdecl("curl_multi_remove_handle")
  public func curlMultiRemoveHandle(_ multi: OpaquePointer?, _ handle: OpaquePointer?) -> Int32 {
    NativeCurl.function(
      "curl_multi_remove_handle",
      as: (@convention(c) (OpaquePointer?, OpaquePointer?) -> Int32).self
    )(multi, handle)
  }

  @_cdecl("curl_multi_perform")
  public func curlMultiPerform(_ multi: OpaquePointer?, _ running: UnsafeMutablePointer<Int32>?)
    -> Int32
  {
    NativeCurl.function(
      "curl_multi_perform",
      as: (@convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> Int32).self)(
        multi, running)
  }

  @_cdecl("curl_multi_info_read")
  public func curlMultiInfoRead(_ multi: OpaquePointer?, _ remaining: UnsafeMutablePointer<Int32>?)
    -> OpaquePointer?
  {
    NativeCurl.function(
      "curl_multi_info_read",
      as: (@convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> OpaquePointer?).self)(
        multi, remaining)
  }
#endif
