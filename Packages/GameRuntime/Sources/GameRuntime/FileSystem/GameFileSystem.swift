#if os(iOS)
  import Darwin
  import Foundation
  import GameRuntimeABI
  import InstallationFeature
  import Synchronization

  /// Path resolution for the file functions the retargeted game imports from this library.
  enum GameFileSystem {
    static let bundle = VirtualGameBundle(
      dataRoot: GameInstallationLayout.current.destination.path(percentEncoded: false),
      executable: Bundle.main.executablePath ?? "")

    private static let virtualPrefix = Array((bundle.contents + "/").utf8CString.dropLast())
    private static let corrections = Mutex<[String: String?]>([:])

    /// Runs `call` with the real path for `path`; a game-data lookup that fails with ENOENT is
    /// retried once with the letter case found on disk.
    static func withRealPath<Result>(
      _ path: UnsafePointer<CChar>?, failed: (Result) -> Bool,
      call: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
      guard let path else { return call(nil) }
      let isVirtual = virtualPrefix.withUnsafeBufferPointer {
        strncmp(path, $0.baseAddress!, $0.count) == 0
      }
      if isVirtual, let real = bundle.resolve(String(cString: path)) {
        return real.withCString { retried(call($0), real, failed, call) }
      }
      return retried(call(path), String(cString: path), failed, call)
    }

    private static func retried<Result>(
      _ result: Result, _ path: @autoclosure () -> String, _ failed: (Result) -> Bool,
      _ call: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
      guard failed(result), errno == ENOENT else { return result }
      let path = path()
      guard bundle.dataRoot(containing: path) != nil else {
        errno = ENOENT
        return result
      }
      let corrected =
        corrections.withLock { $0[path] }
        ?? {
          let found = bundle.caseCorrected(path)
          corrections.withLock { $0[path] = found }
          return found
        }()
      guard let corrected else {
        errno = ENOENT
        return result
      }
      return corrected.withCString(call)
    }
  }

  @_cdecl("_NSGetExecutablePath")
  public func gameRuntimeExecutablePath(
    _ buffer: UnsafeMutablePointer<CChar>?, _ size: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    let path = Array(GameFileSystem.bundle.virtualExecutable.utf8CString)
    guard let size else { return -1 }
    guard let buffer, Int(size.pointee) >= path.count else {
      size.pointee = UInt32(path.count)
      return -1
    }
    path.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: $0.count) }
    return 0
  }

  @_cdecl("GameRuntimeOpenFile")
  public func gameRuntimeOpenFile(_ path: UnsafePointer<CChar>?, _ flags: Int32, _ mode: Int32)
    -> Int32
  {
    let descriptor = GameFileSystem.withRealPath(
      path, failed: { $0 < 0 },
      call: {
        GameRuntimeSystemOpen($0, flags, mode)
      })
    if descriptor >= 0, flags & O_ACCMODE == O_RDONLY, let path {
      CDPRSession.didOpen(descriptor, path: path)
    }
    return descriptor
  }

  @_cdecl("close")
  public func gameRuntimeClose(_ descriptor: Int32) -> Int32 {
    let result = SystemCall.close(descriptor)
    let error = errno
    CDPRSession.didClose(descriptor, result: result)
    errno = error
    return result
  }

  @_cdecl("stat")
  public func gameRuntimeStat(
    _ path: UnsafePointer<CChar>?, _ information: UnsafeMutablePointer<Darwin.stat>?
  ) -> Int32 {
    GameFileSystem.withRealPath(
      path, failed: { $0 != 0 }, call: { SystemCall.stat($0, information) })
  }

  @_cdecl("access")
  public func gameRuntimeAccess(_ path: UnsafePointer<CChar>?, _ mode: Int32) -> Int32 {
    GameFileSystem.withRealPath(path, failed: { $0 != 0 }, call: { SystemCall.access($0, mode) })
  }

  @_cdecl("fopen")
  public func gameRuntimeOpenStream(_ path: UnsafePointer<CChar>?, _ mode: UnsafePointer<CChar>?)
    -> UnsafeMutablePointer<FILE>?
  {
    GameFileSystem.withRealPath(path, failed: { $0 == nil }, call: { SystemCall.fopen($0, mode) })
  }

  @_cdecl("opendir")
  public func gameRuntimeOpenDirectory(_ path: UnsafePointer<CChar>?) -> UnsafeMutablePointer<DIR>?
  {
    GameFileSystem.withRealPath(path, failed: { $0 == nil }, call: { SystemCall.opendir($0) })
  }

  @_cdecl("realpath$DARWIN_EXTSN")
  public func gameRuntimeRealPath(
    _ path: UnsafePointer<CChar>?, _ resolved: UnsafeMutablePointer<CChar>?
  ) -> UnsafeMutablePointer<CChar>? {
    GameFileSystem.withRealPath(
      path, failed: { $0 == nil }, call: { SystemCall.realpath($0, resolved) })
  }
#endif
