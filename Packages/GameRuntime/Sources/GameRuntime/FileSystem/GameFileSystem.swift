import Darwin
import Foundation
import Synchronization

/// Owns virtual path translation and the one case-correction retry at the POSIX boundary.
final class GameFileSystem: Sendable {
  let bundle: VirtualGameBundle
  private let virtualPrefix: [CChar]
  private let corrections = Mutex<[String: String]>([:])

  init(bundle: VirtualGameBundle) {
    self.bundle = bundle
    virtualPrefix = Array((bundle.contents + "/").utf8CString.dropLast())
  }

  func withRealPath<Result>(
    _ path: UnsafePointer<CChar>?, failed: (Result) -> Bool,
    call: (UnsafePointer<CChar>?) -> Result
  ) -> Result {
    guard let path else { return call(nil) }
    let virtual = virtualPrefix.withUnsafeBufferPointer { prefix in
      guard let start = prefix.baseAddress else { return false }
      return strncmp(path, start, prefix.count) == 0
    }
    if virtual, let resolved = bundle.resolve(String(cString: path)) {
      return resolved.withCString { retry(call($0), path: resolved, failed: failed, call: call) }
    }
    return retry(call(path), path: String(cString: path), failed: failed, call: call)
  }

  func executablePath(
    into buffer: UnsafeMutablePointer<CChar>?, size: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    let path = Array(bundle.virtualExecutable.utf8CString)
    guard let size else { return -1 }
    guard let buffer, Int(size.pointee) >= path.count else {
      size.pointee = UInt32(path.count)
      return -1
    }
    path.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: $0.count) }
    return 0
  }

  private func retry<Result>(
    _ result: Result, path: @autoclosure () -> String, failed: (Result) -> Bool,
    call: (UnsafePointer<CChar>?) -> Result
  ) -> Result {
    let originalError = errno
    guard failed(result), originalError == ENOENT else {
      errno = originalError
      return result
    }
    let path = path()
    guard bundle.dataRoot(containing: path) != nil else {
      errno = originalError
      return result
    }
    let corrected: String?
    if let cached = corrections.withLock({ $0[path] }) {
      corrected = cached
    } else {
      corrected = bundle.caseCorrected(path)
      if let corrected { corrections.withLock { $0[path] = corrected } }
    }
    guard let corrected else {
      errno = originalError
      return result
    }
    let retried = corrected.withCString { pointer in
      let result = call(pointer)
      return (result, errno)
    }
    errno = retried.1
    return retried.0
  }
}

#if os(iOS)
  import GameRuntimeABI
  import InstallationFeature

  extension GameFileSystem {
    static let current = GameFileSystem(
      bundle: VirtualGameBundle(
        dataRoot: GameInstallationLayout.current.destination.path(percentEncoded: false),
        executable: Bundle.main.executablePath ?? ""))
  }

  @_cdecl("_NSGetExecutablePath")
  public func gameRuntimeExecutablePath(
    _ buffer: UnsafeMutablePointer<CChar>?, _ size: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    GameFileSystem.current.executablePath(into: buffer, size: size)
  }

  @_cdecl("GameRuntimeOpenFile")
  public func gameRuntimeOpenFile(_ path: UnsafePointer<CChar>?, _ flags: Int32, _ mode: Int32)
    -> Int32
  {
    let descriptor = GameFileSystem.current.withRealPath(
      path, failed: { $0 < 0 }, call: { GameRuntimeSystemOpen($0, flags, mode) })
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
    GameFileSystem.current.withRealPath(
      path, failed: { $0 != 0 }, call: { SystemCall.stat($0, information) })
  }

  @_cdecl("access")
  public func gameRuntimeAccess(_ path: UnsafePointer<CChar>?, _ mode: Int32) -> Int32 {
    GameFileSystem.current.withRealPath(
      path, failed: { $0 != 0 }, call: { SystemCall.access($0, mode) })
  }

  @_cdecl("fopen")
  public func gameRuntimeOpenStream(_ path: UnsafePointer<CChar>?, _ mode: UnsafePointer<CChar>?)
    -> UnsafeMutablePointer<FILE>?
  {
    GameFileSystem.current.withRealPath(
      path, failed: { $0 == nil }, call: { SystemCall.fopen($0, mode) })
  }

  @_cdecl("opendir")
  public func gameRuntimeOpenDirectory(_ path: UnsafePointer<CChar>?) -> UnsafeMutablePointer<DIR>?
  {
    GameFileSystem.current.withRealPath(
      path, failed: { $0 == nil }, call: { SystemCall.opendir($0) })
  }

  @_cdecl("realpath$DARWIN_EXTSN")
  public func gameRuntimeRealPath(
    _ path: UnsafePointer<CChar>?, _ resolved: UnsafeMutablePointer<CChar>?
  ) -> UnsafeMutablePointer<CChar>? {
    GameFileSystem.current.withRealPath(
      path, failed: { $0 == nil }, call: { SystemCall.realpath($0, resolved) })
  }
#endif
