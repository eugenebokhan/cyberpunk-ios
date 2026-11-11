import Foundation
import MachO
import Testing

@testable import GameBuildTools

struct MachOTests {
  @Test func malformedImagesAreRejected() {
    for data in [
      Data(), Data([0xcf, 0xfa, 0xed, 0xfe]),
      words([0xfeed_facf, 0x0100_0007, 0, 6, 0, 0, 0, 0]),
      words([0xfeed_facf, 0x0100_000c, 0, 6, UInt32.max, 0, 0, 0]),
      words([0xfeed_facf, 0x0100_000c, 0, 6, 1, 8, 0, 0, 0xc, UInt32.max]),
    ] {
      #expect(throws: BuildFailure.self) { _ = try MachO(data) }
    }
  }

  @Test func libraryDeduplicationPreservesMachOLayout() throws {
    let input = image([build, library(framework("CoreGraphics")), library(framework("Security"))])
    var output = try MachO(input)
    try output.retarget(minimum: "27.0", sdk: "27.1")
    #expect(output.commands.count == 2)
    #expect(try MachO(Data(output.bytes)).commands.count == 2)
    #expect(output.bytes.count == input.count)
    #expect(String(decoding: output.bytes, as: UTF8.self).contains(MachO.runtimePath))
    #expect(!String(decoding: output.bytes, as: UTF8.self).contains("Versions/A"))
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.1") }
  }

  @Test func unknownMainExecutableIsRejected() throws {
    var input = try MachO(image([build], type: UInt32(MH_EXECUTE)))
    #expect(throws: BuildFailure.self) { try input.validateAppStoreExecutable(patch: false) }
  }

  @Test func rejectedTransformationLeavesTheOriginalImageIntact() throws {
    let input = image([build, library(framework("CoreGraphics"))], type: UInt32(MH_EXECUTE))
    var output = try MachO(input)
    let offsets = output.commands.map(\.offset)
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.2") }
    #expect(output.bytes == Array(input))
    #expect(output.commands.map(\.offset) == offsets)
  }

  @Test func ownedRuntimePathAndMergedCommandsPreservePayloadOffsets() throws {
    let marker = Data([0xab, 0xcd, 0xef])
    let input = image(
      [build, library("/usr/lib/libcurl.4.dylib"), library(framework("CoreGraphics"))],
      payload: marker)
    var output = try MachO(input)
    try output.retarget(minimum: "27.0", sdk: "27.2")
    #expect(output.commands.count == 2)
    #expect(output.commands[1].size == 56)
    #expect(output.bytes.count == input.count)
    #expect(Array(output.bytes.suffix(marker.count)) == Array(marker))
  }

  @Test func mergingARequiredLibraryPromotesAnEarlierWeakLoad() throws {
    var output = try MachO(
      image([
        build, library(framework("CoreGraphics"), kind: UInt32(LC_LOAD_WEAK_DYLIB)),
        library(framework("Security")),
      ]))
    try output.retarget(minimum: "27.0", sdk: "27.2")
    #expect(output.commands[1].kind == LC_LOAD_DYLIB)
  }

  @Test func aUniversalImageSelectsOnlyThePlainARM64Slice() throws {
    let thin = image([build, library(framework("CoreGraphics"))])
    let fat = bigWords([FAT_MAGIC, 1, UInt32(CPU_TYPE_ARM64), 0, 28, UInt32(thin.count), 0])
    let parsed = try MachO(fat + thin)
    #expect(parsed.bytes == Array(thin))
    #expect(throws: BuildFailure.self) {
      _ = try MachO(bigWords([FAT_MAGIC, UInt32.max]))
    }
    #expect(throws: BuildFailure.self) {
      _ = try MachO(bigWords([FAT_MAGIC, 1, UInt32(CPU_TYPE_ARM64), 0, UInt32.max, 16, 0]))
    }
  }

  @Test func wideBindOffsetsSurviveLibraryRenumbering() throws {
    let binding = Data([0x20, 2, 0x70] + Array(repeating: UInt8(0xff), count: 9) + [1, 0x90, 0])
    let fixture = bindings(binding)
    var output = try MachO(fixture.data)
    try output.retarget(minimum: "27.0", sdk: "27.1")
    #expect(output.bytes[fixture.offset + 1] == 1)
    #expect(Array(output.bytes[(fixture.offset + 2)...]) == Array(binding.dropFirst(2)))
  }

  @Test func threadedBindOperandsAreParsedWithoutChangingUnrelatedBytes() throws {
    let binding = Data([0xd0, 2, 0x12, 0xd1, 0x3f, 0x60, 0x7f, 0])
    let fixture = bindings(binding)
    var output = try MachO(fixture.data)
    try output.retarget(minimum: "27.0", sdk: "27.2")
    #expect(Array(output.bytes[fixture.offset...]) == [0xd0, 2, 0x11, 0xd1, 0x3f, 0x60, 0x7f, 0])
  }

  @Test(arguments: [
    Data([0xf0, 0]), Data([0xd0, 0x80]), Data([0xd2]), Data([0x70, 0x80]),
    Data([0x60] + Array(repeating: UInt8(0xff), count: 9) + [1]),
  ])
  func malformedBindingStreamsFailWithoutMutation(_ binding: Data) throws {
    let fixture = bindings(binding)
    var output = try MachO(fixture.data)
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.2") }
    #expect(output.bytes == Array(fixture.data))
  }

  @Test(arguments: [UInt32(1), 2, 3])
  func chainedOrdinalsPreserveWeakImportsSpecialValuesAndAddends(_ format: UInt32) throws {
    let fixture = chained(format)
    var output = try MachO(fixture.data)
    try output.retarget(minimum: "27.0", sdk: "27.2")
    let wide = format == 3
    let mask: UInt64 = wide ? 0xffff : 0xff
    let expected: [UInt64] = [1, 1, 2, mask]
    for index in 0..<4 {
      let offset = fixture.offset + 28 + index * fixture.stride
      let old = wide ? read64(fixture.data, at: offset) : UInt64(read32(fixture.data, at: offset))
      let current =
        wide
        ? read64(Data(output.bytes), at: offset) : UInt64(read32(Data(output.bytes), at: offset))
      #expect(current == (old & ~mask) | expected[index])
      let wordSize = wide ? 8 : 4
      #expect(
        Array(output.bytes[offset + wordSize..<offset + fixture.stride])
          == Array(fixture.data[offset + wordSize..<offset + fixture.stride]))
    }
    #expect(try output.requiredRuntimeOverrides() == ["_open"])
  }

  @Test func chainedNamesCannotEscapeTheirDeclaredPayload() throws {
    let fixture = chained(1)
    var input = fixture.data
    let symbolOffset = read32(input, at: fixture.offset + 12)
    input.replaceSubrange(
      fixture.command + 12..<fixture.command + 16, with: words([symbolOffset]))
    var output = try MachO(input)
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.2") }
    #expect(output.bytes == Array(input))
  }

  @Test func chainedTablesCannotOverlapTheFixupHeader() throws {
    let fixture = chained(1)
    var input = fixture.data
    input.replaceSubrange(fixture.offset + 8..<fixture.offset + 12, with: words([0]))
    var output = try MachO(input)
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.2") }
    #expect(output.bytes == Array(input))
  }

  @Test func chainedWideReservedBitsAreRejected() throws {
    let fixture = chained(3)
    var input = fixture.data
    let offset = fixture.offset + 28
    input.replaceSubrange(
      offset..<offset + 8, with: longWords([read64(input, at: offset) | 0x20000]))
    var output = try MachO(input)
    #expect(throws: BuildFailure.self) { try output.retarget(minimum: "27.0", sdk: "27.2") }
  }

  @Test func symbolStringAlignmentPreservesFollowingPayloadAndRefreshesCommandOffsets() throws {
    let prefix = [build, library(framework("CoreGraphics"))]
    let payloadOffset = 32 + prefix.reduce(0) { $0 + $1.count } + 24 + 16
    let stringOffset = payloadOffset + 16 + 3
    let symbols = Data([0]) + Data("_plain".utf8) + Data([0])
    let padding = (8 - stringOffset % 8) % 8
    let followingOffset = stringOffset + symbols.count + padding
    let symbolCommand = words([
      UInt32(LC_SYMTAB), 24, UInt32(payloadOffset), 1, UInt32(stringOffset), UInt32(symbols.count),
    ])
    let following = words([UInt32(LC_FUNCTION_STARTS), 16, UInt32(followingOffset), 1])
    let entry = words([1]) + Data([UInt8(N_EXT), 0, 0x40, 1]) + longWords([0])
    let payload =
      entry + Data([0xa1, 0xa2, 0xa3]) + symbols
      + Data(repeating: 0, count: padding) + Data([0x91])
    var output = try MachO(image(prefix + [symbolCommand, following], payload: payload))
    try output.retarget(minimum: "27.0", sdk: "27.2")
    let current = try #require(output.commands.first(where: { $0.kind == LC_SYMTAB }))
    let actualOffset = Int(read32(Data(output.bytes), at: current.offset + 16))
    #expect(actualOffset == stringOffset + padding)
    #expect(Array(output.bytes[actualOffset..<actualOffset + symbols.count]) == Array(symbols))
    #expect(output.bytes[followingOffset] == 0x91)
    #expect(output.bytes[payloadOffset + 6] == 0x40)
  }

  @Test func reservedSymbolOrdinalsRemainSpecialWithLargeLibraryTables() throws {
    let libraries =
      [library(framework("CoreGraphics")), library(framework("Security"))]
      + (0..<252).map { library("@rpath/Library\($0).dylib") }
    let prefix = [build] + libraries
    let start = 32 + prefix.reduce(0) { $0 + $1.count } + 24
    let strings = Data([0]) + Data("_plain".utf8) + Data([0])
    let command = words([
      UInt32(LC_SYMTAB), 24, UInt32(start), 4, UInt32(start + 64), UInt32(strings.count),
    ])
    let entries = [UInt8(0), 0xfd, 0xfe, 0xff].reduce(Data()) { data, ordinal in
      data + words([1]) + Data([UInt8(N_EXT), 0, 0x40, ordinal]) + longWords([0])
    }
    var output = try MachO(image(prefix + [command], payload: entries + strings))
    try output.retarget(minimum: "27.0", sdk: "27.2")
    #expect([0, 1, 2, 3].map { output.bytes[start + $0 * 16 + 7] } == [0, 0xfc, 0xfe, 0xff])
    #expect([0, 1, 2, 3].allSatisfy { output.bytes[start + $0 * 16 + 6] == 0x40 })
  }

  @Test func invalidVersionsDoNotOverflow() throws {
    #expect(try MachO.version("27.1") == 0x001b_0100)
    for value in ["", "27.", "27..1", "27.256", "65536.0", "-1", "+27", "27.0.0.1", "version"] {
      #expect(throws: BuildFailure.self) { try MachO.version(value) }
    }
  }

  private var build: Data { words([UInt32(LC_BUILD_VERSION), 24, 1, 0x000f_0500, 0x000f_0500, 0]) }

  private func framework(_ name: String) -> String {
    "/System/Library/Frameworks/\(name).framework/Versions/A/\(name)"
  }

  private func image(_ commands: [Data], payload: Data = Data(), type: UInt32 = UInt32(MH_DYLIB))
    -> Data
  {
    let table = commands.reduce(Data(), +)
    return words([
      MH_MAGIC_64, UInt32(CPU_TYPE_ARM64), 0, type, UInt32(commands.count), UInt32(table.count), 0,
      0,
    ])
      + table + payload
  }

  private func bindings(_ stream: Data) -> (data: Data, offset: Int) {
    let prefix = [build, library(framework("CoreGraphics")), library(framework("Security"))]
    let offset = 32 + prefix.reduce(0) { $0 + $1.count } + 48
    let command = words([
      UInt32(LC_DYLD_INFO_ONLY), 48, 0, 0, UInt32(offset), UInt32(stream.count), 0, 0, 0, 0, 0, 0,
    ])
    return (image(prefix + [command], payload: stream), offset)
  }

  private func chained(_ format: UInt32) -> (data: Data, command: Int, offset: Int, stride: Int) {
    let prefix = [
      build, library(framework("CoreGraphics")), library(framework("Security")),
      library(framework("Foundation")),
    ]
    let command = 32 + prefix.reduce(0) { $0 + $1.count }
    let offset = command + 16
    let stride = format == 1 ? 4 : format == 2 ? 8 : 16
    let names = ["_open", "_close", "_malloc", "_lookup"]
    let wide = format == 3
    let ordinals: [UInt64] = [3, 2, 3, wide ? 0xffff : 0xff]
    var strings = Data()
    var records = Data()
    for (index, name) in names.enumerated() {
      let value =
        ordinals[index] | (index == 1 ? (wide ? 0x10000 : 0x100) : 0)
        | (UInt64(strings.count) << (wide ? 32 : 9))
      records += wide ? longWords([value, 0x1122_3344_5566_7788]) : words([UInt32(value)])
      if format == 2 { records += words([0xdead_beef]) }
      strings += Data(name.utf8) + Data([0])
    }
    let payload = words([0, 0, 28, UInt32(28 + records.count), 4, format, 0]) + records + strings
    let fixups = words([UInt32(LC_DYLD_CHAINED_FIXUPS), 16, UInt32(offset), UInt32(payload.count)])
    return (image(prefix + [fixups], payload: payload), command, offset, stride)
  }

  private func library(_ path: String, kind: UInt32 = UInt32(LC_LOAD_DYLIB)) -> Data {
    let string = Array(path.utf8) + [0]
    let size = (24 + string.count + 7) & ~7
    return words([kind, UInt32(size), 24, 0, 0, 0]) + Data(string)
      + Data(repeating: 0, count: size - 24 - string.count)
  }

  private func words(_ values: [UInt32]) -> Data {
    Data(values.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
  }

  private func bigWords(_ values: [UInt32]) -> Data {
    Data(
      values.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ((3 - $0) * 8)) } })
  }

  private func longWords(_ values: [UInt64]) -> Data {
    Data(values.flatMap { word in (0..<8).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
  }

  private func read32(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes {
      UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
  }

  private func read64(_ data: Data, at offset: Int) -> UInt64 {
    data.withUnsafeBytes {
      UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }
  }
}

@Suite @MainActor struct PhoneSettingsTests {
  private var fixture: Data {
    Data(
      #"""
      {"version":152,"options":[
        {"group_name":"/graphics/presets","options":[
          {"name":"QuickPresets","type":"string_list","value":"Custom","index":0},
          {"name":"ResolutionScaling","type":"string_list","value":"MetalFX","index":1,"values":["Off","MetalFX"]},
          {"name":"FrameGeneration","type":"string_list","index":0,"values":["Off","FSR3","MetalFX"]},
          {"name":"TextureQuality","type":"string_list","value":"High","index":1,"values":["Low","High"]},
          {"name":"DynamicResolutionScaling","type":"bool","value":true}
        ]},
        {"group_name":"/graphics/raytracing","options":[
          {"name":"RayTracing","type":"bool","value":true}
        ]},
        {"group_name":"/graphics/advanced","options":[
          {"name":"AntiAliasing","type":"string_list","value":"","index":-1},
          {"name":"ShadowMeshQuality","type":"string_list","value":"High","index":1,"values":["Low","High"]},
          {"name":"Number","type":"int","value":9,"default_value":3}
        ]},
        {"group_name":"/video/display","options":[
          {"name":"HDRModes","type":"string_list","value":"HDR10_PQ","index":1}
        ]}
      ]}
      """#.utf8)
  }

  @Test func appliesPhonePolicyAndOmitsRendererSelectedOptions() throws {
    let result = try MacGame.phoneSettings(fixture)
    let json = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
    let groups = try #require(json["data"] as? [[String: Any]])
    let options = groups.flatMap { $0["options"] as? [[String: Any]] ?? [] }
    func option(_ name: String) throws -> [String: Any] {
      try #require(options.first { $0["name"] as? String == name })
    }
    #expect(try option("TextureQuality")["value"] as? String == "Low")
    #expect(try option("TextureQuality")["index"] as? Int == 0)
    #expect(try option("ResolutionScaling")["value"] as? String == "Off")
    #expect(try option("RayTracing")["value"] as? Bool == false)
    #expect(try option("DynamicResolutionScaling")["value"] as? Bool == false)
    #expect(try option("Number")["value"] as? Int == 3)
    #expect(!options.contains { $0["name"] as? String == "AntiAliasing" })
    #expect(!options.contains { $0["name"] as? String == "HDRModes" })
  }

  @Test func rejectsIncompleteOrMalformedSettings() {
    for text in ["[]", "{}", "{", #"{"version":152,"data":[]}"#] {
      #expect(throws: Error.self) { try MacGame.phoneSettings(Data(text.utf8)) }
    }
  }

  @Test func rejectsMalformedPolicyValuesAndUnsupportedChoices() {
    let text = String(decoding: fixture, as: UTF8.self)
    for replacement in [
      text.replacingOccurrences(
        of: #""type":"bool","value":true"#, with: #""type":"bool","value":1"#),
      text.replacingOccurrences(of: #""values":["Low","High"]"#, with: #""values":[{}, "High"]"#),
      text.replacingOccurrences(of: #""values":["Off","MetalFX"]"#, with: #""values":["MetalFX"]"#),
    ] {
      #expect(throws: Error.self) { try MacGame.phoneSettings(Data(replacement.utf8)) }
    }
  }
}
