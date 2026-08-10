import MachO

/// A Mach-O image loaded in this process.
struct MachOImage {
  let header: UnsafePointer<mach_header_64>
  let slide: Int

  static var main: MachOImage {
    guard let game = loaded(named: "Cyberpunk2077") else {
      preconditionFailure("The game executable is not loaded")
    }
    return game
  }

  static func loaded(named name: String) -> MachOImage? {
    (0..<_dyld_image_count()).first { index in
      guard let path = _dyld_get_image_name(index) else { return false }
      return String(cString: path).split(separator: "/").last.map(String.init) == name
    }.map(image(at:))
  }

  private static func image(at index: UInt32) -> MachOImage {
    MachOImage(
      header: UnsafeRawPointer(_dyld_get_image_header(index)!).assumingMemoryBound(
        to: mach_header_64.self),
      slide: _dyld_get_image_vmaddr_slide(index))
  }

  private var commands: [UnsafeRawPointer] {
    var command = UnsafeRawPointer(header.advanced(by: 1))
    return (0..<header.pointee.ncmds).map { _ in
      defer { command += Int(command.load(as: load_command.self).cmdsize) }
      return command
    }
  }

  private func first<Command>(_ kind: UInt32, as _: Command.Type) -> Command? {
    commands.first { $0.load(as: load_command.self).cmd == kind }?
      .loadUnaligned(as: Command.self)
  }

  var uuid: [UInt8]? {
    first(0x1b, as: uuid_command.self).map { command in
      withUnsafeBytes(of: command.uuid) { Array($0) }
    }
  }

  /// The executable's entry point, `main`.
  var entryPoint: UnsafeRawPointer? {
    first(0x8000_0028, as: entry_point_command.self).map {
      UnsafeRawPointer(header) + Int($0.entryoff)
    }
  }

  func segment(named name: String) -> segment_command_64? {
    commands.lazy.filter { $0.load(as: load_command.self).cmd == 0x19 }
      .map { $0.loadUnaligned(as: segment_command_64.self) }
      .first { segment in
        withUnsafeBytes(of: segment.segname) {
          String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
          == name
      }
  }

  func containsCode(_ address: UnsafeRawPointer) -> Bool {
    guard let text = segment(named: "__TEXT") else { return false }
    let start = UInt(text.vmaddr) &+ UInt(bitPattern: slide)
    return (start..<start + UInt(text.vmsize)).contains(UInt(bitPattern: address))
  }

  /// Addresses of `__TEXT` symbols with the given C names, including local symbols, from the
  /// image's symbol table.
  func codeSymbols(named names: Set<String>) -> [String: [UnsafeRawPointer]] {
    guard let table = first(0x2, as: symtab_command.self),
      let linkedit = segment(named: "__LINKEDIT"), let text = segment(named: "__TEXT")
    else { return [:] }
    let base = UnsafeRawPointer(bitPattern: slide + Int(linkedit.vmaddr) - Int(linkedit.fileoff))!
    let strings = (base + Int(table.stroff)).assumingMemoryBound(to: CChar.self)
    let symbols = (base + Int(table.symoff)).bindMemory(
      to: nlist_64.self, capacity: Int(table.nsyms))
    var found: [String: [UnsafeRawPointer]] = [:]
    for symbol in UnsafeBufferPointer(start: symbols, count: Int(table.nsyms)) {
      guard Int32(symbol.n_type) & N_STAB == 0, Int32(symbol.n_type) & N_TYPE == N_SECT,
        symbol.n_un.n_strx < table.strsize,
        (text.vmaddr..<text.vmaddr + text.vmsize).contains(symbol.n_value)
      else { continue }
      let name = String(cString: strings + Int(symbol.n_un.n_strx))
      guard name.hasPrefix("_"), names.contains(String(name.dropFirst())) else { continue }
      found[String(name.dropFirst()), default: []].append(
        UnsafeRawPointer(bitPattern: slide + Int(symbol.n_value))!)
    }
    return found
  }
}
