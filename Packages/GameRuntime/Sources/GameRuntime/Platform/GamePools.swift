import Darwin

/// The engine reserves its memory pools through two `reserve(size, align)` functions. The build
/// tools replace their `add x1, x0, size` with a `nop`, so the pool's end is whatever `mmap`
/// returns in x1: reservations above 8 GB get 8 GB plus a no-access guard, and the engine works
/// within the end it is told. A reservation that cannot be made fails; it is never shrunk further
/// or placed over other mappings.
enum GamePools {
  static let capacity = 8 << 30
  static let guardSize = 512 << 20

  /// Whether `instructions`, read at an `mmap` return address, are a patched pool-end site:
  /// `cmn x0, #1; b.eq <failure>; nop`.
  static func isPatchedPoolSite(_ instructions: (UInt32, UInt32, UInt32)) -> Bool {
    instructions.0 == 0xb100_041f && instructions.1 & 0xff00_001f == 0x5400_0000
      && instructions.2 == 0xd503_201f
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
    guard address == nil, descriptor < 0, flags & MAP_ANON != 0, flags & MAP_FIXED == 0,
      length > GamePools.capacity, let returnAddress, MachOImage.main.containsCode(returnAddress),
      GamePools.isPatchedPoolSite(
        (
          returnAddress.load(as: UInt32.self),
          returnAddress.load(fromByteOffset: 4, as: UInt32.self),
          returnAddress.load(fromByteOffset: 8, as: UInt32.self)
        ))
    else {
      let base = SystemCall.mmap(address, length, protection, flags, descriptor, offset)
      return GameRuntimeMapping(
        base: base, end: base == failed ? 0 : UInt(bitPattern: base) + UInt(length))
    }
    let base = SystemCall.mmap(
      nil, GamePools.capacity + GamePools.guardSize, protection, flags, -1, 0)
    guard let base, base != failed,
      SystemCall.mprotect(base + GamePools.capacity, GamePools.guardSize, PROT_NONE) == 0
    else {
      RuntimeLog.write("pool reservation of \(length >> 20) MB failed (errno \(errno))")
      errno = ENOMEM
      return GameRuntimeMapping(base: failed, end: 0)
    }
    RuntimeLog.write(
      "pool reservation of \(length >> 20) MB capped at \(GamePools.capacity >> 20) MB")
    return GameRuntimeMapping(base: base, end: UInt(bitPattern: base) + UInt(GamePools.capacity))
  }
#endif
