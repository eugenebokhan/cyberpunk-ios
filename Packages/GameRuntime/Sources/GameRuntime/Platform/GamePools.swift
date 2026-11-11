import Darwin

enum GamePools {
  static let capacity = 8 << 30
  static let guardSize = 512 << 20

  static func isPatchedPoolSite(_ instructions: (UInt32, UInt32, UInt32)) -> Bool {
    instructions.0 == 0xb100_041f && instructions.1 & 0xff00_001f == 0x5400_0000
      && instructions.2 == 0xd503_201f
  }

  static func reserve(
    map: (Int) -> UnsafeMutableRawPointer?,
    protect: (UnsafeMutableRawPointer, Int) -> Int32,
    release: (UnsafeMutableRawPointer, Int) -> Int32
  ) -> UnsafeMutableRawPointer? {
    let failed = UnsafeMutableRawPointer(bitPattern: -1)
    let size = capacity + guardSize
    guard let base = map(size) else {
      errno = ENOMEM
      return failed
    }
    guard base != failed else { return failed }
    guard protect(base + capacity, guardSize) == 0 else {
      let error = errno
      _ = release(base, size)
      errno = error
      return failed
    }
    return base
  }
}

#if os(iOS)
  import GameRuntimeABI

  @_cdecl("GameRuntimeMapMemory")
  public func gameRuntimeMapMemory(
    _ address: UnsafeMutableRawPointer?, _ length: Int, _ protection: Int32, _ flags: Int32,
    _ descriptor: Int32, _ offset: off_t, _ returnAddress: UnsafeRawPointer?
  ) -> GameRuntimeMapping {
    let failed = UnsafeMutableRawPointer(bitPattern: -1)
    let patchedSite =
      address == nil && descriptor < 0 && flags & MAP_ANON != 0 && flags & MAP_FIXED == 0
      && length > GamePools.capacity
      && returnAddress.map {
        MachOImage.main.containsCode($0) && MachOImage.main.containsCode($0 + 8)
          && GamePools.isPatchedPoolSite(
            (
              $0.load(as: UInt32.self), $0.load(fromByteOffset: 4, as: UInt32.self),
              $0.load(fromByteOffset: 8, as: UInt32.self)
            ))
      } == true
    let base: UnsafeMutableRawPointer?
    let mappedLength: Int
    if patchedSite {
      base = GamePools.reserve(
        map: { SystemCall.mmap(nil, $0, protection, flags, -1, 0) },
        protect: { SystemCall.mprotect($0, $1, PROT_NONE) },
        release: { SystemCall.munmap($0, $1) })
      mappedLength = GamePools.capacity
    } else {
      base = SystemCall.mmap(address, length, protection, flags, descriptor, offset)
      mappedLength = length
    }
    if base == failed { return GameRuntimeMapping(base: failed, end: 0) }
    return GameRuntimeMapping(
      base: base, end: UInt(bitPattern: base) &+ UInt(bitPattern: mappedLength))
  }
#endif
