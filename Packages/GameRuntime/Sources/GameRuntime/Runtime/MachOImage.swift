import MachO

struct MachOImage {
  let header: UnsafePointer<mach_header_64>
  let slide: Int
  private let commands: [UnsafeRawPointer]

  init?(header: UnsafePointer<mach_header_64>, slide: Int) {
    let image = header.pointee
    guard image.magic == MH_MAGIC_64, image.cputype == CPU_TYPE_ARM64,
      image.ncmds <= image.sizeofcmds / UInt32(MemoryLayout<load_command>.size)
    else { return nil }
    let start = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    let length = Int(image.sizeofcmds)
    var cursor = 0
    var parsed: [UnsafeRawPointer] = []
    for _ in 0..<image.ncmds {
      guard length - cursor >= MemoryLayout<load_command>.size else { return nil }
      let pointer = start.advanced(by: cursor)
      let command = pointer.loadUnaligned(as: load_command.self)
      let size = Int(command.cmdsize)
      guard size >= MemoryLayout<load_command>.size, size.isMultiple(of: 8),
        size <= length - cursor
      else { return nil }
      parsed.append(pointer)
      cursor += size
    }
    guard cursor == length else { return nil }
    self.header = header
    self.slide = slide
    commands = parsed
  }

  static var main: MachOImage {
    guard let image = loaded(named: "Cyberpunk2077") else {
      preconditionFailure("The game executable is not loaded")
    }
    return image
  }

  static func loaded(named name: String) -> MachOImage? {
    var selected: MachOImage?
    for index in 0..<_dyld_image_count() {
      guard let path = _dyld_get_image_name(index),
        let fileName = String(cString: path).split(separator: "/").last, fileName == name,
        let pointer = _dyld_get_image_header(index),
        let image = MachOImage(
          header: UnsafeRawPointer(pointer).assumingMemoryBound(to: mach_header_64.self),
          slide: _dyld_get_image_vmaddr_slide(index))
      else { continue }
      guard selected == nil else { return nil }
      selected = image
    }
    return selected
  }

  private func command<Value>(_ kind: UInt32, as: Value.Type) -> Value? {
    guard
      let pointer = commands.first(where: {
        let item = $0.loadUnaligned(as: load_command.self)
        return item.cmd == kind && item.cmdsize >= MemoryLayout<Value>.size
      })
    else { return nil }
    return pointer.loadUnaligned(as: Value.self)
  }

  var uuid: [UInt8]? {
    guard let item = command(UInt32(LC_UUID), as: uuid_command.self) else { return nil }
    return withUnsafeBytes(of: item.uuid) { Array($0) }
  }

  var entryPoint: UnsafeRawPointer? {
    guard let entry = command(UInt32(LC_MAIN), as: entry_point_command.self),
      let text = segment(named: "__TEXT"), text.fileoff == 0,
      entry.entryoff < text.filesize, entry.entryoff < text.vmsize,
      let offset = Int(exactly: entry.entryoff)
    else { return nil }
    return UnsafeRawPointer(header).advanced(by: offset)
  }

  func segment(named name: String) -> segment_command_64? {
    for pointer in commands {
      let item = pointer.loadUnaligned(as: load_command.self)
      guard item.cmd == LC_SEGMENT_64,
        item.cmdsize >= MemoryLayout<segment_command_64>.size
      else { continue }
      let segment = pointer.loadUnaligned(as: segment_command_64.self)
      let sectionBytes = UInt64(segment.nsects) * UInt64(MemoryLayout<section_64>.size)
      guard sectionBytes <= UInt64(item.cmdsize) - UInt64(MemoryLayout<segment_command_64>.size)
      else { return nil }
      let matches = withUnsafeBytes(of: segment.segname) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) == name
      }
      if matches { return segment }
    }
    return nil
  }

  func containsCode(_ address: UnsafeRawPointer) -> Bool {
    guard let text = segment(named: "__TEXT"), text.initprot & VM_PROT_EXECUTE != 0 else {
      return false
    }
    let start = UInt(text.vmaddr) &+ UInt(bitPattern: slide)
    let (end, overflow) = start.addingReportingOverflow(UInt(text.vmsize))
    return !overflow && start <= UInt(bitPattern: address) && UInt(bitPattern: address) < end
  }

  func codeSymbols(named names: Set<String>) -> [String: [UnsafeRawPointer]] {
    guard let table = command(UInt32(LC_SYMTAB), as: symtab_command.self),
      let linkedit = segment(named: "__LINKEDIT"), let text = segment(named: "__TEXT"),
      let symbols = mappedBytes(
        offset: UInt64(table.symoff),
        count: UInt64(table.nsyms) * UInt64(MemoryLayout<nlist_64>.size),
        in: linkedit),
      let strings = mappedBytes(
        offset: UInt64(table.stroff), count: UInt64(table.strsize), in: linkedit)
    else { return [:] }
    let (textEnd, overflow) = text.vmaddr.addingReportingOverflow(text.vmsize)
    guard !overflow else { return [:] }
    var found: [String: [UnsafeRawPointer]] = [:]
    for index in 0..<Int(table.nsyms) {
      let symbol = symbols.loadUnaligned(
        fromByteOffset: index * MemoryLayout<nlist_64>.size, as: nlist_64.self)
      guard Int32(symbol.n_type) & N_STAB == 0, Int32(symbol.n_type) & N_TYPE == N_SECT,
        symbol.n_value >= text.vmaddr, symbol.n_value < textEnd,
        Int(symbol.n_un.n_strx) < strings.count
      else { continue }
      let tail = strings[Int(symbol.n_un.n_strx)...]
      guard let end = tail.firstIndex(of: 0), tail.first == UInt8(ascii: "_") else { continue }
      let name = String(decoding: strings[(Int(symbol.n_un.n_strx) + 1)..<end], as: UTF8.self)
      guard names.contains(name),
        let address = UnsafeRawPointer(bitPattern: UInt(symbol.n_value) &+ UInt(bitPattern: slide))
      else { continue }
      if found[name]?.contains(address) != true { found[name, default: []].append(address) }
    }
    return found
  }

  private func mappedBytes(
    offset: UInt64, count: UInt64, in segment: segment_command_64
  ) -> UnsafeRawBufferPointer? {
    guard offset >= segment.fileoff else { return nil }
    let relative = offset - segment.fileoff
    guard relative <= segment.filesize, count <= segment.filesize - relative,
      relative <= segment.vmsize, count <= segment.vmsize - relative,
      let length = Int(exactly: count), let displacement = Int(exactly: relative)
    else { return nil }
    let start = UInt(segment.vmaddr) &+ UInt(bitPattern: slide)
    let (address, overflow) = start.addingReportingOverflow(UInt(displacement))
    guard !overflow, let pointer = UnsafeRawPointer(bitPattern: address) else { return nil }
    return UnsafeRawBufferPointer(start: pointer, count: length)
  }
}
