import Foundation
import MachO

struct MachO {
  struct Command {
    let kind: UInt32
    let offset: Int
    let size: Int
  }

  private struct Import {
    let offset: Int
    let ordinal: Int
    let wide: Bool
    let weak: Bool
    let name: String
    let nameRange: Range<Int>
  }

  private struct LibraryPlan {
    var ordinals: [Int: Int] = [:]
    var names: [Int: String] = [:]
    var kinds: [Int: UInt32] = [:]
    var removed: Set<Int> = []
    var runtimeOrdinal: Int?
  }

  private struct Section {
    let address: UInt64
    let file: Range<Int>
  }

  static let runtimePath = "@rpath/libGameRuntime.dylib"
  static let rerouted: Set<String> = [
    "__NSGetExecutablePath", "_sysctlbyname", "_mmap", "_opendir", "_realpath$DARWIN_EXTSN",
    "_stat", "_access", "_fopen", "_open", "_close", "_sysctl",
    "_pthread_set_qos_class_self_np", "_pthread_setschedparam", "_pthread_attr_setschedpolicy",
  ]
  private static let libraryCommands: Set<UInt32> = [
    UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB),
    UInt32(LC_LOAD_UPWARD_DYLIB),
  ]
  private static let replacedFrameworks: Set<String> = [
    "AppKit", "Cocoa", "IOKit", "Carbon", "AudioUnit", "CoreAudio", "GameKit",
    "CoreGraphics", "Security", "Metal",
  ]
  private static let aliases = [
    "_OBJC_CLASS_$_NSColor": "_OBJC_CLASS_$_UIColor",
    "_OBJC_CLASS_$_NSFont": "_OBJC_CLASS_$_UIFont",
  ]
  private static let headerSize = MemoryLayout<mach_header_64>.size
  private(set) var bytes: [UInt8]
  private(set) var commands: [Command] = []

  init(_ data: Data) throws {
    bytes = Array(data)
    if try read(0, as: UInt32.self) == FAT_CIGAM {
      let count = Int(try read(4, as: UInt32.self).byteSwapped)
      let entrySize = MemoryLayout<fat_arch>.size
      guard bytes.count >= 8, count <= (bytes.count - 8) / entrySize else {
        throw BuildFailure("Invalid universal architecture table")
      }
      var selected: Range<Int>?
      for index in 0..<count {
        let entry = 8 + index * entrySize
        let cpu = try read(entry, as: UInt32.self).byteSwapped
        let subtype = try read(entry + 4, as: UInt32.self).byteSwapped
        guard cpu == UInt32(CPU_TYPE_ARM64), subtype & 0x00ff_ffff == 0 else { continue }
        let start = Int(try read(entry + 8, as: UInt32.self).byteSwapped)
        let size = Int(try read(entry + 12, as: UInt32.self).byteSwapped)
        let alignment = try read(entry + 16, as: UInt32.self).byteSwapped
        guard start >= 8 + count * entrySize, size > 0, alignment < 32,
          start % (1 << Int(alignment)) == 0
        else { throw BuildFailure("Invalid ARM64 universal slice") }
        selected = try region(start, size)
        break
      }
      guard let selected else { throw BuildFailure("No plain ARM64 architecture") }
      bytes = Array(bytes[selected])
    }
    guard try read(0, as: UInt32.self) == MH_MAGIC_64,
      try read(4, as: UInt32.self) == UInt32(CPU_TYPE_ARM64),
      try read(8, as: UInt32.self) & 0x00ff_ffff == 0
    else { throw BuildFailure("Expected a little-endian plain ARM64 Mach-O image") }
    try parseCommands()
  }

  var type: UInt32 { get throws { try read(12) } }

  var uuid: [UInt8]? {
    get throws {
      guard let command = commands.first(where: { $0.kind == LC_UUID }) else { return nil }
      guard command.size >= MemoryLayout<uuid_command>.size else {
        throw BuildFailure("Truncated UUID command")
      }
      return Array(bytes[command.offset + 8..<command.offset + 24])
    }
  }

  func requiredRuntimeOverrides() throws -> Set<String> {
    let libraries = try commands.filter { Self.libraryCommands.contains($0.kind) }.map(commandName)
    return Set(
      try imports().compactMap { item in
        guard !item.weak, item.ordinal > 0, item.ordinal <= libraries.count,
          libraries[item.ordinal - 1] == Self.runtimePath, Self.rerouted.contains(item.name)
        else { return nil }
        return item.name
      })
  }

  mutating func retarget(minimum: String, sdk: String) throws {
    let minimumVersion = try Self.version(minimum)
    let sdkVersion = try Self.version(sdk)
    var result = self
    let versions = commands.filter { $0.kind == LC_BUILD_VERSION }
    guard versions.count == 1, let version = versions.first, version.size >= 24,
      try result.read(version.offset + 8, as: UInt32.self) == PLATFORM_MACOS,
      try Int(result.read(version.offset + 20, as: UInt32.self)) <= (version.size - 24) / 8,
      !commands.contains(where: { $0.kind == LC_VERSION_MIN_MACOSX })
    else { throw BuildFailure("Expected one complete modern macOS build-version command") }
    for command in commands where command.kind == LC_ENCRYPTION_INFO_64 {
      guard command.size >= MemoryLayout<encryption_info_command_64>.size,
        try result.read(command.offset + 16, as: UInt32.self) == 0
      else { throw BuildFailure("Encrypted or malformed executable is unsupported") }
    }
    let plan = try result.planLibraries()
    try result.rewriteImports(plan)
    try result.alignSymbolStrings()
    if try result.type == MH_EXECUTE {
      try result.validateAppStoreExecutable(patch: true)
      try result.adaptMemoryReservations()
      try result.adaptWatchdog()
    }
    if try commands.contains(where: {
      try $0.kind == LC_ID_DYLIB && commandName($0).hasSuffix("/libREDGalaxy64.dylib")
    }) {
      try result.adaptCDPRLibrary()
    }
    try result.writeCommands(plan, minimum: minimumVersion, sdk: sdkVersion)
    self = result
  }

  mutating func validateAppStoreExecutable(patch: Bool) throws {
    let expectedUUID: [UInt8] = [
      0x03, 0x8b, 0x50, 0xeb, 0xa6, 0x7e, 0x37, 0x5a,
      0xb0, 0x7b, 0x95, 0xf0, 0xc0, 0x46, 0x35, 0x30,
    ]
    guard try uuid == expectedUUID,
      !find(Array("_OBJC_CLASS_$_BAAssetPackManager\0".utf8), limit: 1).isEmpty
    else { throw BuildFailure("Expected the supported Mac App Store executable, version 2.5.0") }
    for (address, words): (UInt64, [UInt32]) in [
      (0x1_0002_939c, [0xb940_1408, 0x1200_7500, 0xd65f_03c0]),
      (0x1_0002_9954, [0xb940_1408, 0x531e_7d08, 0x3400_0048, 0xf940_0000]),
      (0x1_02b0_84cc, [0xd101_43ff, 0xa903_4ff4, 0xa904_7bfd, 0x9101_03fd]),
      (
        0x1_0003_18d0,
        [
          0xf003_b974, 0xf943_0e80, 0x954a_0672, 0xaa13_03e2, 0x954a_0378,
          0xf943_0e80, 0x954a_066e, 0x9003_bd22, 0x913a_4042, 0x9549_fb2b,
        ]
      ),
      (0x1_0003_19a4, [0x9003_bd28, 0x913f_4108, 0x9100_4108]),
    ] {
      try expect(words, at: address)
    }
    if patch {
      try write(UInt32(0x1400_0035), at: fileOffset(0x1_0003_18d0, count: 4))
    }
  }

  static func mappedLibrary(_ path: String) -> String? {
    let parts = path.split(separator: "/")
    if path.hasPrefix("/System/Library/Frameworks/"), parts.count == 7,
      parts[4] == "Versions", parts[5].count == 1, parts[3] == parts[6] + ".framework"
    {
      let framework = String(parts[6])
      return replacedFrameworks.contains(framework)
        ? runtimePath : "/System/Library/Frameworks/\(framework).framework/\(framework)"
    }
    if path == "/usr/lib/libcurl.4.dylib" { return runtimePath }
    let frameworkRoot = "@executable_path/../Frameworks/"
    return path.hasPrefix(frameworkRoot) ? "@rpath/" + path.dropFirst(frameworkRoot.count) : nil
  }

  static func version(_ value: String) throws -> UInt32 {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { throw BuildFailure("Invalid OS version") }
    var packed: UInt32 = 0
    for (index, part) in parts.enumerated() {
      guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = UInt32(part), number <= (index == 0 ? 65535 : 255)
      else { throw BuildFailure("Invalid OS version") }
      packed |= number << (index == 0 ? 16 : index == 1 ? 8 : 0)
    }
    return packed
  }

  private mutating func parseCommands() throws {
    let count = Int(try read(16, as: UInt32.self))
    let table = try region(Self.headerSize, Int(read(20, as: UInt32.self)))
    guard count <= table.count / MemoryLayout<load_command>.size else {
      throw BuildFailure("Load-command count exceeds its table")
    }
    var position = table.lowerBound
    var parsed: [Command] = []
    for _ in 0..<count {
      _ = try region(position, 8, within: table)
      let size = Int(try read(position + 4, as: UInt32.self))
      guard size >= 8, size.isMultiple(of: 8) else {
        throw BuildFailure("Invalid load-command size")
      }
      let bounds = try region(position, size, within: table)
      parsed.append(Command(kind: try read(position), offset: position, size: size))
      position = bounds.upperBound
    }
    guard position == table.upperBound else { throw BuildFailure("Incomplete load-command table") }
    commands = parsed
  }

  private func planLibraries() throws -> LibraryPlan {
    var plan = LibraryPlan()
    var first: [String: (ordinal: Int, offset: Int)] = [:]
    var ordinal = 0
    for command in commands where Self.libraryCommands.contains(command.kind) {
      ordinal += 1
      let original = try commandName(command)
      let name = Self.mappedLibrary(original) ?? original
      if let previous = first[name] {
        plan.ordinals[ordinal] = previous.ordinal
        plan.removed.insert(command.offset)
        if plan.kinds[previous.offset] == LC_LOAD_WEAK_DYLIB, command.kind != LC_LOAD_WEAK_DYLIB {
          plan.kinds[previous.offset] = command.kind
        }
      } else {
        let index = first.count + 1
        first[name] = (index, command.offset)
        plan.ordinals[ordinal] = index
        plan.names[command.offset] = name
        plan.kinds[command.offset] = command.kind
        if name == Self.runtimePath { plan.runtimeOrdinal = index }
      }
    }
    guard let runtime = plan.runtimeOrdinal, runtime <= 240 else {
      throw BuildFailure("The runtime requires a representable chained-import library ordinal")
    }
    return plan
  }

  private mutating func writeCommands(_ plan: LibraryPlan, minimum: UInt32, sdk: UInt32) throws {
    let capacity = Int(try read(20, as: UInt32.self))
    var table: [UInt8] = []
    var count: UInt32 = 0
    for command in commands where !plan.removed.contains(command.offset) {
      var body = Array(bytes[command.offset..<command.offset + command.size])
      if command.kind == LC_BUILD_VERSION {
        body.replaceSubrange(8..<20, with: Self.words([UInt32(PLATFORM_IOS), minimum, sdk]))
      }
      if let kind = plan.kinds[command.offset] {
        body.replaceSubrange(0..<4, with: Self.words([kind]))
      }
      if Self.libraryCommands.contains(command.kind) || command.kind == LC_ID_DYLIB
        || command.kind == LC_RPATH
      {
        let old = try commandName(command)
        let name: String
        if command.kind == LC_RPATH {
          name =
            ["@executable_path/../Frameworks", "@loader_path/../Frameworks"].contains(old)
            ? "@executable_path/Frameworks" : old
        } else {
          name = plan.names[command.offset] ?? Self.mappedLibrary(old) ?? old
        }
        let prefix = Int(try read(command.offset + 8, as: UInt32.self))
        body = Array(body.prefix(prefix)) + Array(name.utf8) + [0]
        body += repeatElement(0, count: (8 - body.count % 8) % 8)
        guard let size = UInt32(exactly: body.count) else {
          throw BuildFailure("Load command is too large")
        }
        body.replaceSubrange(4..<8, with: Self.words([size]))
      }
      guard body.count <= capacity - table.count else {
        throw BuildFailure("Retargeted commands exceed the existing header space")
      }
      table += body
      count += 1
    }
    let size = UInt32(table.count)
    table += repeatElement(0, count: capacity - table.count)
    bytes.replaceSubrange(Self.headerSize..<Self.headerSize + capacity, with: table)
    try write(count, at: 16)
    try write(size, at: 20)
    try parseCommands()
  }

  private func imports() throws -> [Import] {
    var result: [Import] = []
    for command in commands where command.kind == LC_DYLD_CHAINED_FIXUPS {
      guard command.size >= MemoryLayout<linkedit_data_command>.size else {
        throw BuildFailure("Truncated chained-fixups command")
      }
      let payload = try region(
        Int(read(command.offset + 8, as: UInt32.self)),
        Int(read(command.offset + 12, as: UInt32.self)))
      _ = try region(payload.lowerBound, 28, within: payload)
      guard try read(payload.lowerBound, as: UInt32.self) == 0,
        try read(payload.lowerBound + 24, as: UInt32.self) == 0
      else { throw BuildFailure("Unsupported chained-fixups version or compressed symbol table") }
      let count = Int(try read(payload.lowerBound + 16, as: UInt32.self))
      let format = try read(payload.lowerBound + 20, as: UInt32.self)
      guard (1...3).contains(format) else {
        throw BuildFailure("Unsupported chained-import format")
      }
      let stride = format == 1 ? 4 : format == 2 ? 8 : 16
      let start = try relative(
        payload.lowerBound, UInt64(read(payload.lowerBound + 8, as: UInt32.self)), in: payload)
      let symbols = try relative(
        payload.lowerBound, UInt64(read(payload.lowerBound + 12, as: UInt32.self)), in: payload)
      guard count <= (payload.upperBound - start) / stride,
        count == 0 || (start >= payload.lowerBound + 28 && symbols >= payload.lowerBound + 28)
      else {
        throw BuildFailure("Chained-import table exceeds its payload")
      }
      for index in 0..<count {
        let offset = start + index * stride
        let wide = format == 3
        let value = try wide ? read(offset, as: UInt64.self) : UInt64(read(offset, as: UInt32.self))
        let mask: UInt64 = wide ? 0xffff : 0xff
        let raw = value & mask
        let ordinal = raw > mask - 15 ? Int(raw) - Int(mask) - 1 : Int(raw)
        let nameOffset = try relative(symbols, value >> (wide ? 32 : 9), in: payload)
        let symbol = try cString(nameOffset, within: payload)
        if wide, value & 0xfffe_0000 != 0 {
          throw BuildFailure("Reserved chained-import bits are set")
        }
        result.append(
          Import(
            offset: offset, ordinal: ordinal, wide: wide,
            weak: value & (wide ? 0x10000 : 0x100) != 0,
            name: symbol.name, nameRange: symbol.range))
      }
    }
    return result
  }

  private mutating func rewriteImports(_ plan: LibraryPlan) throws {
    for item in try imports() {
      try rename(item.name, at: item.nameRange)
      let ordinal =
        Self.rerouted.contains(item.name)
        ? plan.runtimeOrdinal : plan.ordinals[item.ordinal]
      guard let ordinal else { continue }
      if item.wide {
        let value: UInt64 = try read(item.offset)
        try write((value & ~0xffff) | UInt64(ordinal), at: item.offset)
      } else {
        let value: UInt32 = try read(item.offset)
        try write((value & ~0xff) | UInt32(ordinal), at: item.offset)
      }
    }
    for command in commands {
      if command.kind == LC_SYMTAB {
        guard command.size >= MemoryLayout<symtab_command>.size else {
          throw BuildFailure("Truncated symbol-table command")
        }
        let start = Int(try read(command.offset + 8, as: UInt32.self))
        let count = Int(try read(command.offset + 12, as: UInt32.self))
        guard start <= bytes.count, count <= (bytes.count - start) / 16 else {
          throw BuildFailure("Symbol table exceeds the file")
        }
        let strings = try region(
          Int(read(command.offset + 16, as: UInt32.self)),
          Int(read(command.offset + 20, as: UInt32.self)))
        for index in 0..<count {
          let offset = start + index * 16
          guard bytes[offset + 4] & UInt8(N_STAB | N_TYPE) == N_UNDF else { continue }
          let nameOffset = try relative(
            strings.lowerBound, UInt64(read(offset, as: UInt32.self)), in: strings)
          let symbol = try cString(nameOffset, within: strings)
          try rename(symbol.name, at: symbol.range)
          let previous = Int(bytes[offset + 7])
          if (1...Int(MAX_LIBRARY_ORDINAL)).contains(previous),
            let ordinal = plan.ordinals[previous]
          {
            guard ordinal <= MAX_LIBRARY_ORDINAL else {
              throw BuildFailure("Symbol ordinal is too large")
            }
            bytes[offset + 7] = UInt8(ordinal)
          }
        }
      }
      if command.kind == LC_DYLD_INFO || command.kind == LC_DYLD_INFO_ONLY {
        guard command.size >= MemoryLayout<dyld_info_command>.size else {
          throw BuildFailure("Truncated dyld-info command")
        }
        for field in [16, 24, 32] {
          let stream = try region(
            Int(read(command.offset + field, as: UInt32.self)),
            Int(read(command.offset + field + 4, as: UInt32.self)))
          try rewriteBindings(stream, ordinals: plan.ordinals)
        }
      }
    }
  }

  private mutating func rewriteBindings(_ stream: Range<Int>, ordinals: [Int: Int]) throws {
    var cursor = stream.lowerBound
    func leb(signed: Bool = false) throws -> (value: UInt64, range: Range<Int>) {
      let start = cursor
      var value: UInt64 = 0
      for index in 0..<10 {
        guard cursor < stream.upperBound else { throw BuildFailure("Truncated bind operand") }
        let byte = bytes[cursor]
        cursor += 1
        if index == 9, signed ? ![0, 0x7f].contains(byte) : byte > 1 {
          throw BuildFailure("Bind operand overflows 64 bits")
        }
        value |= UInt64(byte & 0x7f) << (index * 7)
        if byte & 0x80 == 0 { return (value, start..<cursor) }
      }
      throw BuildFailure("Unterminated bind operand")
    }
    while cursor < stream.upperBound {
      let position = cursor
      let instruction = bytes[cursor]
      cursor += 1
      let immediate = Int(instruction & 15)
      switch instruction & 0xf0 {
      case UInt8(BIND_OPCODE_DONE), UInt8(BIND_OPCODE_SET_DYLIB_SPECIAL_IMM),
        UInt8(BIND_OPCODE_SET_TYPE_IMM), UInt8(BIND_OPCODE_DO_BIND),
        UInt8(BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED):
        break
      case UInt8(BIND_OPCODE_SET_DYLIB_ORDINAL_IMM):
        if let ordinal = ordinals[immediate] { bytes[position] = 0x10 | UInt8(ordinal) }
      case UInt8(BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB):
        let operand = try leb()
        if let old = Int(exactly: operand.value), let ordinal = ordinals[old] {
          var value = ordinal
          for offset in operand.range {
            bytes[offset] = UInt8(value & 0x7f) | (offset < operand.range.upperBound - 1 ? 0x80 : 0)
            value >>= 7
          }
          guard value == 0 else {
            throw BuildFailure("Library ordinal no longer fits its bind operand")
          }
        }
      case UInt8(BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM):
        let symbol = try cString(cursor, within: stream)
        try rename(symbol.name, at: symbol.range)
        cursor = symbol.range.upperBound + 1
      case UInt8(BIND_OPCODE_SET_ADDEND_SLEB):
        _ = try leb(signed: true)
      case UInt8(BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB), UInt8(BIND_OPCODE_ADD_ADDR_ULEB),
        UInt8(BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB):
        _ = try leb()
      case UInt8(BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB):
        _ = try leb()
        _ = try leb()
      case UInt8(BIND_OPCODE_THREADED):
        if immediate == BIND_SUBOPCODE_THREADED_SET_BIND_ORDINAL_TABLE_SIZE_ULEB {
          _ = try leb()
        } else if immediate != BIND_SUBOPCODE_THREADED_APPLY {
          throw BuildFailure("Unsupported threaded-bind operation")
        }
      default:
        throw BuildFailure("Unsupported dyld bind opcode")
      }
    }
  }

  private mutating func alignSymbolStrings() throws {
    guard let symbolTable = commands.first(where: { $0.kind == LC_SYMTAB }) else { return }
    guard symbolTable.size >= 24 else { throw BuildFailure("Truncated symbol-table command") }
    let strings = try region(
      Int(read(symbolTable.offset + 16, as: UInt32.self)),
      Int(read(symbolTable.offset + 20, as: UInt32.self)))
    let padding = (8 - strings.lowerBound % 8) % 8
    guard padding > 0 else { return }
    var boundary = bytes.count
    let payloadCommands: Set<UInt32> = [
      UInt32(LC_CODE_SIGNATURE), UInt32(LC_SEGMENT_SPLIT_INFO), UInt32(LC_FUNCTION_STARTS),
      UInt32(LC_DATA_IN_CODE), UInt32(LC_DYLIB_CODE_SIGN_DRS), UInt32(LC_LINKER_OPTIMIZATION_HINT),
      UInt32(LC_DYLD_EXPORTS_TRIE), UInt32(LC_DYLD_CHAINED_FIXUPS),
    ]
    func include(_ start: Int, _ count: Int) throws {
      let payload = try region(start, count)
      if !payload.isEmpty, payload.lowerBound >= strings.upperBound {
        boundary = min(boundary, payload.lowerBound)
      }
    }
    for command in commands {
      if payloadCommands.contains(command.kind) {
        guard command.size >= 16 else { throw BuildFailure("Truncated link-edit command") }
        try include(
          Int(read(command.offset + 8, as: UInt32.self)),
          Int(read(command.offset + 12, as: UInt32.self)))
      } else if command.kind == LC_DYLD_INFO || command.kind == LC_DYLD_INFO_ONLY {
        guard command.size >= 48 else { throw BuildFailure("Truncated dyld-info command") }
        for field in stride(from: 8, through: 40, by: 8) {
          try include(
            Int(read(command.offset + field, as: UInt32.self)),
            Int(read(command.offset + field + 4, as: UInt32.self)))
        }
      }
    }
    guard padding <= boundary - strings.upperBound,
      bytes[strings.upperBound..<strings.upperBound + padding].allSatisfy({ $0 == 0 })
    else { throw BuildFailure("Symbol strings have no unused alignment space") }
    let contents = Array(bytes[strings])
    bytes.replaceSubrange(
      strings.lowerBound + padding..<strings.upperBound + padding, with: contents)
    bytes.replaceSubrange(
      strings.lowerBound..<strings.lowerBound + padding, with: repeatElement(0, count: padding))
    try write(UInt32(strings.lowerBound + padding), at: symbolTable.offset + 16)
  }

  private mutating func adaptMemoryReservations() throws {
    let patches: [(address: UInt64, expected: [UInt32], offset: UInt64, word: UInt32)] = [
      (0x1_0000_eec8, [0xd2c0_0088, 0xf900_23e8], 0, 0xd2c0_0048),
      (0x1_0000_ef08, [0xd2c0_0209, 0xa902_27e8], 0, 0xd2c0_0049),
      (0x1_0000_ef4c, [0xd2c0_0109, 0xa900_a7e8], 0, 0xd2c0_0049),
      (
        0x1_0001_4738, [0x954a_6b8e, 0xb100_041f, 0x5400_00a0, 0x8b13_0001, 0xa941_7bfd], 12,
        0xd503_201f
      ),
      (
        0x1_0001_47ac, [0x954a_6b71, 0xb100_041f, 0x5400_0100, 0x8b13_0001, 0xa941_7bfd], 12,
        0xd503_201f
      ),
    ]
    for patch in patches { try expect(patch.expected, at: patch.address) }
    for patch in patches {
      try write(patch.word, at: fileOffset(patch.address + patch.offset, count: 4))
    }
  }

  private mutating func adaptWatchdog() throws {
    try expect(
      [0x9751_a8d5, 0x3700_0320, 0xb001_d961, 0x910c_0021, 0x5280_0040], at: 0x1_03ac_cdcc)
    try write(UInt32(0x1400_0018), at: fileOffset(0x1_03ac_cdd4, count: 4))
  }

  private mutating func adaptCDPRLibrary() throws {
    guard
      try uuid == [
        0x8c, 0x7a, 0x3a, 0xa6, 0xde, 0x6c, 0x3d, 0xf0,
        0x8a, 0xfb, 0x8a, 0x7f, 0x4a, 0x82, 0x8c, 0x90,
      ]
    else { throw BuildFailure("Unsupported native CDPR library") }
    for address: UInt64 in [0x145798, 0x1457b8] {
      try expect([0xf000_0fc1, 0x910f_6021], at: address)
    }
    for address: UInt64 in [0x145798, 0x1457b8] {
      try write(UInt32(0xaa1f_03e1), at: fileOffset(address + 4, count: 4))
    }
  }

  private func section(_ name: String) throws -> Section {
    for command in commands where command.kind == LC_SEGMENT_64 {
      guard command.size >= 72 else { throw BuildFailure("Truncated segment command") }
      let count = Int(try read(command.offset + 64, as: UInt32.self))
      guard count <= (command.size - 72) / 80 else { throw BuildFailure("Invalid section table") }
      for index in 0..<count {
        let offset = command.offset + 72 + index * 80
        let field = try cString(offset, within: offset..<offset + 16, fixed: true)
        if field.name == name {
          let size = try read(offset + 40, as: UInt64.self)
          guard let count = Int(exactly: size) else { throw BuildFailure("Section size overflow") }
          return Section(
            address: try read(offset + 32),
            file: try region(Int(read(offset + 48, as: UInt32.self)), count))
        }

      }
    }
    throw BuildFailure("Missing required section \(name)")
  }

  private func fileOffset(_ address: UInt64, count: Int) throws -> Int {
    for command in commands where command.kind == LC_SEGMENT_64 {
      guard command.size >= 72 else { throw BuildFailure("Truncated segment command") }
      let name = try cString(
        command.offset + 8, within: command.offset + 8..<command.offset + 24, fixed: true)
      guard name.name == "__TEXT" else { continue }
      let base: UInt64 = try read(command.offset + 24)
      let size: UInt64 = try read(command.offset + 48)
      let start: UInt64 = try read(command.offset + 40)
      guard address >= base, address - base <= size, UInt64(count) <= size - (address - base),
        let offset = Int(exactly: start), let length = Int(exactly: size)
      else { throw BuildFailure("Native adaptation lies outside the text segment") }
      let file = try region(offset, length)
      return try relative(offset, address - base, in: file)
    }
    throw BuildFailure("Missing native text segment")
  }

  private func expect(_ expected: [UInt32], at address: UInt64) throws {
    let offset = try fileOffset(address, count: expected.count * 4)
    for (index, word) in expected.enumerated() {
      guard try read(offset + index * 4, as: UInt32.self) == word else {
        throw BuildFailure(
          "Unexpected native instruction at \(String(address + UInt64(index * 4), radix: 16))")
      }
    }
  }

  private func commandName(_ command: Command) throws -> String {
    let minimum = command.kind == LC_RPATH ? 12 : 24
    guard command.size >= minimum else { throw BuildFailure("Truncated library-path command") }
    let offset = Int(try read(command.offset + 8, as: UInt32.self))
    guard offset >= minimum, offset < command.size else {
      throw BuildFailure("Invalid library-path offset")
    }
    return try cString(
      command.offset + offset, within: command.offset..<command.offset + command.size
    ).name
  }

  private mutating func rename(_ name: String, at range: Range<Int>) throws {
    guard let replacement = Self.aliases[name] else { return }
    guard replacement.utf8.count == range.count else {
      throw BuildFailure("Symbol alias changes its storage size")
    }
    bytes.replaceSubrange(range, with: replacement.utf8)
  }

  private func cString(_ offset: Int, within bounds: Range<Int>, fixed: Bool = false) throws
    -> (name: String, range: Range<Int>)
  {
    _ = try region(offset, 0, within: bounds)
    let tail = bytes[offset..<bounds.upperBound]
    guard let end = tail.firstIndex(of: 0) ?? (fixed ? bounds.upperBound : nil),
      let name = String(bytes: bytes[offset..<end], encoding: .utf8)
    else { throw BuildFailure("Invalid or unterminated Mach-O string") }
    return (name, offset..<end)
  }

  private func region(_ offset: Int, _ count: Int, within bounds: Range<Int>? = nil) throws
    -> Range<Int>
  {
    let bounds = bounds ?? 0..<bytes.count
    guard offset >= bounds.lowerBound, offset <= bounds.upperBound,
      count >= 0, count <= bounds.upperBound - offset
    else { throw BuildFailure("Mach-O range exceeds its containing data") }
    return offset..<offset + count
  }

  private func relative(_ base: Int, _ displacement: UInt64, in bounds: Range<Int>) throws -> Int {
    _ = try region(base, 0, within: bounds)
    guard displacement <= UInt64(bounds.upperBound - base) else {
      throw BuildFailure("Mach-O offset overflow")
    }
    return base + Int(displacement)
  }

  private func read<T: FixedWidthInteger & BitwiseCopyable>(_ offset: Int, as type: T.Type = T.self)
    throws -> T
  {
    _ = try region(offset, MemoryLayout<T>.size)
    return bytes.withUnsafeBytes {
      T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self))
    }
  }

  private mutating func write<T: FixedWidthInteger & BitwiseCopyable>(_ value: T, at offset: Int)
    throws
  {
    let bounds = try region(offset, MemoryLayout<T>.size)
    var encoded = value.littleEndian
    withUnsafeBytes(of: &encoded) { bytes.replaceSubrange(bounds, with: $0) }
  }

  private func find(_ pattern: [UInt8], in bounds: Range<Int>? = nil, limit: Int) -> [Int] {
    let bounds = bounds ?? 0..<bytes.count
    guard !pattern.isEmpty, !bounds.isEmpty else { return [] }
    return bytes.withUnsafeBytes { storage in
      let data = Data(
        bytesNoCopy: UnsafeMutableRawPointer(mutating: storage.baseAddress!), count: storage.count,
        deallocator: .none)
      var result: [Int] = []
      var position = bounds.lowerBound
      while result.count < limit, position < bounds.upperBound,
        let match = data.range(of: Data(pattern), in: position..<bounds.upperBound)
      {
        result.append(match.lowerBound)
        position = match.lowerBound + 1
      }
      return result
    }
  }

  private static func words(_ values: [UInt32]) -> [UInt8] {
    values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
  }
}
