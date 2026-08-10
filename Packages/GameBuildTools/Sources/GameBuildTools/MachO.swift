import Foundation

struct MachO {
  struct Command {
    let kind: UInt32
    let offset: Int
    let size: Int
  }

  struct Section {
    let address: UInt64
    let size: Int
    let offset: Int
  }

  static let runtimePath = "@rpath/libMacShim.dylib"
  private static let dylibs: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x8000_0023]
  private static let frameworks: Set<String> = [
    "AppKit", "Cocoa", "IOKit", "Carbon", "AudioUnit", "CoreAudio", "GameKit",
    "CoreGraphics", "Security", "Metal",
  ]
  static let rerouted: Set<String> = [
    "__NSGetExecutablePath", "_sysctlbyname", "_mmap",
    "_opendir", "_realpath$DARWIN_EXTSN", "_stat", "_access", "_fopen", "_open",
    "_close", "_sysctl", "_pthread_set_qos_class_self_np", "_pthread_setschedparam",
    "_pthread_attr_setschedpolicy",
  ]
  private(set) var bytes: [UInt8]
  private(set) var commands: [Command] = []

  init(_ data: Data) throws {
    var bytes = [UInt8](data)
    if bytes.count >= 8, Array(bytes.prefix(4)) == [0xca, 0xfe, 0xba, 0xbe] {
      func big(_ offset: Int) throws -> Int {
        guard offset >= 0, offset + 4 <= bytes.count else {
          throw BuildFailure("Truncated fat Mach-O")
        }
        return bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
      }
      let count = try big(4)
      guard count <= (bytes.count - 8) / 20 else { throw BuildFailure("Invalid fat Mach-O table") }
      var slice: Range<Int>?
      for index in 0..<count {
        let entry = 8 + index * 20
        if try big(entry) == 0x0100_000c, try big(entry + 4) & 0xffffff == 0 {
          let start = try big(entry + 8)
          let size = try big(entry + 12)
          guard start <= bytes.count, size <= bytes.count - start else {
            throw BuildFailure("Invalid arm64 slice")
          }
          slice = start..<start + size
          break
        }
      }
      guard let slice else { throw BuildFailure("The game has no plain arm64 slice") }
      bytes = Array(bytes[slice])
    }
    self.bytes = bytes
    guard try read32(0) == 0xfeed_facf, try read32(4) == 0x0100_000c else {
      throw BuildFailure("Expected a little-endian arm64 Mach-O")
    }
    let count = Int(try read32(16))
    let size = Int(try read32(20))
    try check(32, size)
    guard count <= size / 8 else { throw BuildFailure("Invalid Mach-O command count") }
    var offset = 32
    for _ in 0..<count {
      let kind = try read32(offset)
      let length = Int(try read32(offset + 4))
      guard length >= 8, length % 8 == 0, offset <= 32 + size, length <= 32 + size - offset else {
        throw BuildFailure("Invalid Mach-O load command")
      }
      commands.append(Command(kind: kind, offset: offset, size: length))
      offset += length
    }
    guard offset == 32 + size else {
      throw BuildFailure("Mach-O load commands do not fill their table")
    }
  }

  var type: UInt32 { get throws { try read32(12) } }
  var uuid: [UInt8]? {
    get throws {
      guard let command = commands.first(where: { $0.kind == 0x1b }), command.size >= 24 else {
        return nil
      }
      return Array(bytes[command.offset + 8..<command.offset + 24])
    }
  }

  func requiredRuntimeOverrides() throws -> Set<String> {
    let paths = try commands.filter { Self.dylibs.contains($0.kind) }.map(commandName)
    var required = Set<String>()
    for command in commands where command.kind == 0x8000_0034 {
      let base = Int(try read32(command.offset + 8))
      let imports = base + Int(try read32(base + 8))
      let strings = base + Int(try read32(base + 12))
      let count = Int(try read32(base + 16))
      let format = try read32(base + 20)
      guard [1, 2, 3].contains(format), try read32(base + 24) == 0 else {
        throw BuildFailure("Unsupported chained import format")
      }
      let width = format == 1 ? 4 : format == 2 ? 8 : 16
      try check(imports, try product(count, width))
      for index in 0..<count {
        let position = imports + index * width
        let value = format == 3 ? try read64(position) : UInt64(try read32(position))
        let ordinal = Int(value & (format == 3 ? 0xffff : 0xff))
        let weak = value & (format == 3 ? 0x10000 : 0x100) != 0
        guard !weak, ordinal > 0, ordinal <= paths.count,
          paths[ordinal - 1] == Self.runtimePath
        else { continue }
        let name = try string(
          strings + Int(format == 3 ? value >> 32 : value >> 9), end: bytes.count)
        if Self.rerouted.contains(name) { required.insert(name) }
      }
    }
    return required
  }

  mutating func retarget(minimum: String, sdk: String) throws {
    var hasBuildVersion = false
    let redGalaxy = try commands.contains {
      try $0.kind == 0xd && commandName($0).hasSuffix("/libREDGalaxy64.dylib")
    }
    for command in commands {
      if command.kind == 0x24 { throw BuildFailure("Legacy macOS Mach-O is unsupported") }
      if command.kind == 0x32 {
        guard command.size >= 24 else { throw BuildFailure("Truncated build-version command") }
        hasBuildVersion = true
        guard try read32(command.offset + 8) == 1 else {
          throw BuildFailure("The input must target macOS")
        }
        try write32(command.offset + 8, 2)
        try write32(command.offset + 12, Self.version(minimum))
        try write32(command.offset + 16, Self.version(sdk))
      }
      if command.kind == 0x2c, try read32(command.offset + 16) != 0 {
        throw BuildFailure("Encrypted executables are unsupported")
      }
      if Self.dylibs.contains(command.kind) || command.kind == 0x8000_001c || command.kind == 0xd {
        let old = try commandName(command)
        let new: String?
        if command.kind == 0x8000_001c {
          new =
            ["@executable_path/../Frameworks", "@loader_path/../Frameworks"].contains(old)
            ? "@executable_path/Frameworks" : nil
        } else {
          new = Self.mappedLibrary(old)
        }
        if let new, new != old { try replaceName(command, with: new) }
      }
    }
    guard hasBuildVersion else { throw BuildFailure("No modern macOS build-version command") }
    try rerouteImports()
    if try type == 2 {
      try patchPoolEnd()
      try patchWatchdog()
      try patchPoolSizes()
      try validateAppStoreExecutable(patch: true)
    }
    if redGalaxy { try patchSystemTrust() }
    try alignStrings()
    try deduplicateLibraries()
  }

  mutating func validateAppStoreExecutable(patch: Bool) throws {
    guard try uuid == Self.hex("038b50eba67e375ab07b95f0c0463530"),
      !occurrences(Array("_OBJC_CLASS_$_BAAssetPackManager\0".utf8)).isEmpty
    else { throw BuildFailure("Unsupported Mac App Store executable; expected version 2.5.0") }
    let text = try textSegment()
    for (address, expected) in [
      (0x1_0002_939c as UInt64, "081440b900750012c0035fd6"),
      (0x1_0002_9954, "081440b9087d1e5348000034000040f9"),
      (0x1_02b0_84cc, "ff4301d1f44f03a9fd7b04a9fd030191"),
    ] {
      let pattern = Self.hex(expected)
      let offset = try fileOffset(address, count: pattern.count, in: text)
      guard Array(bytes[offset..<offset + pattern.count]) == pattern else {
        throw BuildFailure("Unsupported native CDPR account ABI")
      }
    }
    let start: UInt64 = 0x1_0003_18d0
    let end: UInt64 = 0x1_0003_19a4
    let p = try fileOffset(start, count: 40, in: text)
    let q = try fileOffset(end, count: 12, in: text)
    try expectWords(
      p,
      [
        0xf003_b974, 0xf943_0e80, 0x954a_0672, 0xaa13_03e2, 0x954a_0378,
        0xf943_0e80, 0x954a_066e, 0x9003_bd22, 0x913a_4042, 0x9549_fb2b,
      ])
    try expectWords(q, [0x9003_bd28, 0x913f_4108, 0x9100_4108])
    if patch { try write32(p, 0x1400_0000 | UInt32((end - start) / 4)) }
  }

  static func mappedLibrary(_ path: String) -> String? {
    let components = path.split(separator: "/")
    if path.hasPrefix("/System/Library/Frameworks/"), components.count == 7,
      components[4] == "Versions", components[5].count == 1,
      components[3] == components[6] + ".framework"
    {
      let name = String(components[6])
      return frameworks.contains(name)
        ? runtimePath : "/System/Library/Frameworks/\(name).framework/\(name)"
    }
    if path == "/usr/lib/libcurl.4.dylib" { return runtimePath }
    let prefix = "@executable_path/../Frameworks/"
    return path.hasPrefix(prefix) ? "@rpath/" + path.dropFirst(prefix.count) : nil
  }

  static func version(_ value: String) throws -> UInt32 {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.count <= 3 else { throw BuildFailure("Invalid OS version") }
    let numbers =
      try parts.enumerated().map { index, text -> UInt32 in
        guard let number = UInt32(text), number <= (index == 0 ? 65535 : 255) else {
          throw BuildFailure("Invalid OS version")
        }
        return number
      } + [0, 0]
    return (numbers[0] << 16) | (numbers[1] << 8) | numbers[2]
  }

  private mutating func rerouteImports() throws {
    let renamed = [
      "_OBJC_CLASS_$_NSColor": "_OBJC_CLASS_$_UIColor",
      "_OBJC_CLASS_$_NSFont": "_OBJC_CLASS_$_UIFont",
    ]
    var ordinal: UInt32?
    var index: UInt32 = 0
    for command in commands where Self.dylibs.contains(command.kind) {
      index += 1
      if ordinal == nil, try commandName(command) == Self.runtimePath { ordinal = index }
    }
    guard let ordinal, ordinal <= 250 else {
      throw BuildFailure("Runtime import ordinal is missing or too large")
    }
    for command in commands where command.kind == 0x8000_0034 {
      let base = Int(try read32(command.offset + 8))
      let imports = base + Int(try read32(base + 8))
      let strings = base + Int(try read32(base + 12))
      let count = Int(try read32(base + 16))
      let format = try read32(base + 20)
      guard [1, 2, 3].contains(format), try read32(base + 24) == 0 else {
        throw BuildFailure("Unsupported chained import format")
      }
      let width = format == 1 ? 4 : format == 2 ? 8 : 16
      try check(imports, try product(count, width))
      for index in 0..<count {
        let p = imports + index * width
        let value = format == 3 ? try read64(p) : UInt64(try read32(p))
        let s = strings + Int(format == 3 ? value >> 32 : value >> 9)
        let name = try string(s, end: bytes.count)
        if let replacement = renamed[name] { try replaceString(s, old: name, new: replacement) }
        if Self.rerouted.contains(name) {
          if format == 3 {
            try write64(p, (value & ~0xffff) | UInt64(ordinal))
          } else {
            try write32(p, (UInt32(value) & ~0xff) | ordinal)
          }
        }
      }
    }
    for command in commands where command.kind == 2 {
      let symbols = Int(try read32(command.offset + 8))
      let count = Int(try read32(command.offset + 12))
      let strings = Int(try read32(command.offset + 16))
      try check(symbols, try product(count, 16))
      for index in 0..<count {
        let entry = symbols + index * 16
        if bytes[entry + 4] & 0xee != 0 { continue }
        let s = strings + Int(try read32(entry))
        let name = try string(s, end: bytes.count)
        if let replacement = renamed[name] { try replaceString(s, old: name, new: replacement) }
      }
    }
  }

  private mutating func deduplicateLibraries() throws {
    let libraries = commands.filter { Self.dylibs.contains($0.kind) }
    var first: [String: Int] = [:]
    var remap: [Int: Int] = [:]
    var removed = Set<Int>()
    for (index, command) in libraries.enumerated() {
      let path = try commandName(command)
      if let previous = first[path] {
        removed.insert(command.offset)
        if command.kind != 0x8000_0018, libraries[previous].kind == 0x8000_0018 {
          try write32(libraries[previous].offset, 0xc)
        }
        remap[index + 1] = remap[previous + 1]
      } else {
        first[path] = index
        remap[index + 1] = first.count
      }
    }
    guard !removed.isEmpty else { return }
    guard libraries.count <= 253 else { throw BuildFailure("Too many library ordinals") }
    for command in commands {
      if command.kind == 0x22 || command.kind == 0x8000_0022 {
        for position in [16, 32] {
          try remapBindings(
            start: Int(read32(command.offset + position)),
            size: Int(read32(command.offset + position + 4)), remap: remap)
        }
      }
      if command.kind == 0x8000_0034 {
        let base = Int(try read32(command.offset + 8))
        let imports = base + Int(try read32(base + 8))
        let count = Int(try read32(base + 16))
        let format = try read32(base + 20)
        guard [1, 2, 3].contains(format) else {
          throw BuildFailure("Unsupported chained import format")
        }
        let width = format == 1 ? 4 : format == 2 ? 8 : 16
        try check(imports, try product(count, width))
        for index in 0..<count {
          let p = imports + index * width
          if format == 3 {
            let value = try read64(p)
            if let new = remap[Int(value & 0xffff)] {
              try write64(p, (value & ~0xffff) | UInt64(new))
            }
          } else {
            let value = try read32(p)
            if let new = remap[Int(value & 0xff)] { try write32(p, (value & ~0xff) | UInt32(new)) }
          }
        }
      }
      if command.kind == 2 {
        let symbols = Int(try read32(command.offset + 8))
        let count = Int(try read32(command.offset + 12))
        try check(symbols, try product(count, 16))
        for index in 0..<count {
          let entry = symbols + 16 * index
          if bytes[entry + 4] & 0xee != 0 { continue }
          let descriptor = Int(bytes[entry + 6]) | Int(bytes[entry + 7]) << 8
          if let new = remap[descriptor >> 8] { bytes[entry + 7] = UInt8(new) }
        }
      }
    }
    let size = Int(try read32(20))
    let body = commands.filter { !removed.contains($0.offset) }.flatMap {
      bytes[$0.offset..<$0.offset + $0.size]
    }
    bytes.replaceSubrange(
      32..<32 + size, with: body + [UInt8](repeating: 0, count: size - body.count))
    try write32(16, UInt32(commands.count - removed.count))
    try write32(20, UInt32(body.count))
  }

  private mutating func remapBindings(start: Int, size: Int, remap: [Int: Int]) throws {
    try check(start, size)
    var index = start
    let end = start + size
    func unsigned(_ position: inout Int) throws -> UInt64 {
      var value: UInt64 = 0
      var shift = 0
      while position < end, shift < 64 {
        let byte = bytes[position]
        position += 1
        guard shift < 63 || byte & 0x7e == 0 else { throw BuildFailure("LEB128 overflow") }
        value |= UInt64(byte & 0x7f) << shift
        if byte & 0x80 == 0 {
          return value
        }
        shift += 7
      }
      throw BuildFailure("Truncated LEB128")
    }
    while index < end {
      let byte = bytes[index]
      let opcode = byte & 0xf0
      let immediate = Int(byte & 15)
      index += 1
      switch opcode {
      case 0x10: if let new = remap[immediate] { bytes[index - 1] = 0x10 | UInt8(new) }
      case 0x20:
        let begin = index
        let old = try unsigned(&index)
        if let ordinal = Int(exactly: old), let new = remap[ordinal] {
          for offset in 0..<index - begin {
            bytes[begin + offset] =
              UInt8((new >> (7 * offset)) & 0x7f) | (offset < index - begin - 1 ? 0x80 : 0)
          }
        }
      case 0x40:
        while index < end, bytes[index] != 0 { index += 1 }
        guard index < end else { throw BuildFailure("Truncated bind symbol") }
        index += 1
      case 0x60:
        var count = 0
        var terminated = false
        while index < end, count < 10 {
          let byte = bytes[index]
          index += 1
          count += 1
          if byte & 0x80 == 0 {
            terminated = true
            break
          }
        }
        guard terminated else { throw BuildFailure("Truncated signed LEB128") }
      case 0x70, 0x80, 0xa0: _ = try unsigned(&index)
      case 0xc0:
        _ = try unsigned(&index)
        _ = try unsigned(&index)
      case 0xf0 where immediate == 0: _ = try unsigned(&index)
      default: break
      }
    }
  }

  private mutating func alignStrings() throws {
    guard let command = commands.first(where: { $0.kind == 2 }) else { return }
    let start = Int(try read32(command.offset + 16))
    let size = Int(try read32(command.offset + 20))
    try check(start, size)
    let padding = (8 - start % 8) % 8
    guard padding != 0 else { return }
    let end = start + size
    let kinds: Set<UInt32> = [0x1d, 0x1e, 0x26, 0x29, 0x2b, 0x2e, 0x8000_0033, 0x8000_0034]
    var boundary = bytes.count
    for command in commands where kinds.contains(command.kind) {
      let following = Int(try read32(command.offset + 8))
      if following >= end { boundary = min(boundary, following) }
    }
    guard padding <= boundary - end, bytes[end..<end + padding].allSatisfy({ $0 == 0 }) else {
      throw BuildFailure("Symbol strings lack safe alignment padding")
    }
    let strings = Array(bytes[start..<end])
    bytes.replaceSubrange(start + padding..<end + padding, with: strings)
    bytes.replaceSubrange(start..<start + padding, with: [UInt8](repeating: 0, count: padding))
    try write32(command.offset + 16, UInt32(start + padding))
  }

  // The game consumes mmap's actual end in x1 after these additions are removed.
  private mutating func patchPoolEnd() throws {
    let text = try section("__text")
    var sites: [Int] = []
    var targets = Set<Int64>()
    for p in stride(from: text.offset + 4, to: text.offset + text.size - 8, by: 4) {
      if try read32(p) != 0xb100_041f { continue }
      let call = try read32(p - 4)
      let branch = try read32(p + 4)
      let add = try read32(p + 8)
      if call >> 26 == 0b100101, branch & 0xff00_001f == 0x5400_0000,
        [0x8b13_0001, 0xd503_201f].contains(add)
      {
        let immediate = Int64(Int32(bitPattern: (call & 0x3ffffff) << 6) >> 6)
        targets.insert(Int64(text.address) + Int64(p - 4 - text.offset) + immediate * 4)
        sites.append(p + 8)
      }
    }
    guard sites.count == 2, targets.count == 1 else {
      throw BuildFailure("Unsupported pool-end instructions")
    }
    for site in sites { try write32(site, 0xd503_201f) }
  }

  private mutating func patchPoolSizes() throws {
    for (move, next, register) in [
      (0xd2c0_0088 as UInt32, 0xf900_23e8 as UInt32, 8 as UInt32),
      (0xd2c0_0209, 0xa902_27e8, 9), (0xd2c0_0109, 0xa900_a7e8, 9),
    ] {
      let replacement: UInt32 = 0xd2c0_0000 | (2 << 5) | register
      let sites = occurrences(Self.words([move, next]))
      if sites.count != 1 {
        guard !occurrences(Self.words([replacement, next])).isEmpty else {
          throw BuildFailure("Unsupported pool-size instructions")
        }
      } else {
        try write32(sites[0], replacement)
      }
    }
  }

  private mutating func patchWatchdog() throws {
    let strings = try section("__cstring")
    let text = try section("__text")
    guard
      let offset = occurrences(
        Array("!!! EngineWatchdog timeout!\n\0".utf8),
        in: strings.offset..<strings.offset + strings.size
      ).first
    else { throw BuildFailure("Missing watchdog message") }
    let target = Int64(strings.address) + Int64(offset - strings.offset)
    var sites: [(Int, Int32)] = []
    for p in stride(from: text.offset + 4, to: text.offset + text.size - 8, by: 4) {
      let page = try read32(p)
      guard page & 0x9f00_001f == 0x9000_0001 else { continue }
      let add = try read32(p + 4)
      guard add & 0xffc0_03ff == 0x9100_0021 else { continue }
      let immediate = ((page >> 29) & 3) | (((page >> 5) & 0x7ffff) << 2)
      let signed = Int64(Int32(bitPattern: immediate << 11) >> 11)
      let pc = Int64(text.address) + Int64(p - text.offset)
      guard (pc & ~0xfff) + (signed << 12) + Int64((add >> 10) & 0xfff) == target else { continue }
      let branch = try read32(p - 4)
      guard branch & 0xff00_001f == 0x3700_0000 else { continue }
      let relative = Int32(bitPattern: ((branch >> 5) & 0x3fff) << 18) >> 18
      sites.append((p, relative - 1))
    }
    guard sites.count == 1 else { throw BuildFailure("Unsupported engine watchdog instructions") }
    try write32(sites[0].0, 0x1400_0000 | (UInt32(bitPattern: sites[0].1) & 0x3ffffff))
  }

  private mutating func patchSystemTrust() throws {
    guard try uuid == Self.hex("8c7a3aa6de6c3df08afb8a7f4a828c90") else {
      throw BuildFailure("Unsupported CDPR library")
    }
    let text = try textSegment()
    for address: UInt64 in [0x145798, 0x1457b8] {
      let offset = try fileOffset(address, count: 8, in: text)
      try expectWords(offset, [0xf000_0fc1, 0x910f_6021])
    }
    for address: UInt64 in [0x145798, 0x1457b8] {
      try write32(fileOffset(address, count: 8, in: text) + 4, 0xaa1f_03e1)
    }
  }

  private func section(_ name: String) throws -> Section {
    for command in commands where command.kind == 0x19 {
      let count = Int(try read32(command.offset + 64))
      guard command.size >= 72, count <= (command.size - 72) / 80 else {
        throw BuildFailure("Invalid section table")
      }
      for index in 0..<count {
        let p = command.offset + 72 + index * 80
        if try string(p, end: p + 16, allowUnterminated: true) == name {
          let size = try integer(read64(p + 40))
          let offset = Int(try read32(p + 48))
          try check(offset, size)
          return Section(address: try read64(p + 32), size: size, offset: offset)
        }
      }
    }
    throw BuildFailure("Missing Mach-O section \(name)")
  }

  private func textSegment() throws -> Section {
    guard
      let command = try commands.first(where: {
        try $0.kind == 0x19
          && string($0.offset + 8, end: $0.offset + 24, allowUnterminated: true) == "__TEXT"
      })
    else {
      throw BuildFailure("Missing __TEXT segment")
    }
    let size = try integer(read64(command.offset + 48))
    let offset = try integer(read64(command.offset + 40))
    try check(offset, size)
    return Section(address: try read64(command.offset + 24), size: size, offset: offset)
  }

  private func fileOffset(_ address: UInt64, count: Int, in segment: Section) throws -> Int {
    guard address >= segment.address, address - segment.address <= UInt64(segment.size),
      UInt64(count) <= UInt64(segment.size) - (address - segment.address)
    else { throw BuildFailure("Native patch lies outside __TEXT") }
    return segment.offset + Int(address - segment.address)
  }

  private func commandName(_ command: Command) throws -> String {
    guard command.size >= 12 else { throw BuildFailure("Truncated load-command name") }
    let relative = Int(try read32(command.offset + 8))
    guard relative >= 12, relative < command.size else {
      throw BuildFailure("Invalid load-command name")
    }
    return try string(command.offset + relative, end: command.offset + command.size)
  }

  private mutating func replaceName(_ command: Command, with name: String) throws {
    let relative = Int(try read32(command.offset + 8))
    let value = Array(name.utf8) + [0]
    guard relative < command.size, value.count <= command.size - relative else {
      throw BuildFailure("Runtime path does not fit load command")
    }
    bytes.replaceSubrange(
      command.offset + relative..<command.offset + command.size,
      with: value + [UInt8](repeating: 0, count: command.size - relative - value.count))
  }

  private mutating func replaceString(_ offset: Int, old: String, new: String) throws {
    guard old.utf8.count == new.utf8.count else {
      throw BuildFailure("Symbol replacement changes size")
    }
    try check(offset, old.utf8.count)
    bytes.replaceSubrange(offset..<offset + old.utf8.count, with: new.utf8)
  }

  private func string(_ offset: Int, end: Int, allowUnterminated: Bool = false) throws -> String {
    guard offset >= 0, offset < end, end <= bytes.count else {
      throw BuildFailure("Invalid Mach-O string range")
    }
    let tail = bytes[offset..<end]
    let zero = tail.firstIndex(of: 0)
    guard zero != nil || allowUnterminated else { throw BuildFailure("Unterminated Mach-O string") }
    return String(decoding: bytes[offset..<(zero ?? end)], as: UTF8.self)
  }

  private func occurrences(_ pattern: [UInt8], in range: Range<Int>? = nil) -> [Int] {
    let data = Data(bytes)
    let needle = Data(pattern)
    let range = range ?? 0..<bytes.count
    var cursor = range.lowerBound
    var result: [Int] = []
    while cursor < range.upperBound,
      let found = data.range(of: needle, in: cursor..<range.upperBound)
    {
      result.append(found.lowerBound)
      cursor = found.lowerBound + 1
    }
    return result
  }

  private func expectWords(_ offset: Int, _ words: [UInt32]) throws {
    for (index, expected) in words.enumerated() where try read32(offset + index * 4) != expected {
      throw BuildFailure(
        "Unexpected instruction at file offset \(String(offset + index * 4, radix: 16))")
    }
  }

  private func check(_ offset: Int, _ count: Int) throws {
    guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
      throw BuildFailure("Truncated Mach-O data")
    }
  }

  private func integer(_ value: UInt64) throws -> Int {
    guard let result = Int(exactly: value) else { throw BuildFailure("Mach-O offset overflow") }
    return result
  }

  private func product(_ a: Int, _ b: Int) throws -> Int {
    let result = a.multipliedReportingOverflow(by: b)
    guard !result.overflow else { throw BuildFailure("Mach-O size overflow") }
    return result.partialValue
  }

  private func read32(_ offset: Int) throws -> UInt32 {
    try check(offset, 4)
    return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
  }

  private func read64(_ offset: Int) throws -> UInt64 {
    try check(offset, 8)
    return (0..<8).reduce(0) { $0 | UInt64(bytes[offset + $1]) << ($1 * 8) }
  }

  private mutating func write32(_ offset: Int, _ value: UInt32) throws {
    try check(offset, 4)
    for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
  }

  private mutating func write64(_ offset: Int, _ value: UInt64) throws {
    try check(offset, 8)
    for index in 0..<8 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
  }

  private static func hex(_ value: String) -> [UInt8] {
    stride(from: 0, to: value.count, by: 2).map { position in
      let start = value.index(value.startIndex, offsetBy: position)
      return UInt8(value[start..<value.index(start, offsetBy: 2)], radix: 16)!
    }
  }

  private static func words(_ values: [UInt32]) -> [UInt8] {
    values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
  }
}
