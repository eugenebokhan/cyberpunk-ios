import Foundation
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
    let build = words([0x32, 24, 1, 0x000f_0500, 0x000f_0500, 0])
    let graphics = library(
      "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics")
    let security = library("/System/Library/Frameworks/Security.framework/Versions/A/Security")
    let body = build + graphics + security
    let header = words([0xfeed_facf, 0x0100_000c, 0, 6, 3, UInt32(body.count), 0, 0])
    var image = try MachO(header + body)
    try image.retarget(minimum: "27.0", sdk: "27.1")
    let result = try MachO(Data(image.bytes))
    #expect(result.commands.count == 2)
    #expect(image.bytes.count == header.count + body.count)
    #expect(String(decoding: image.bytes, as: UTF8.self).contains(MachO.runtimePath))
    #expect(!String(decoding: image.bytes, as: UTF8.self).contains("Versions/A"))
    #expect(throws: BuildFailure.self) { try image.retarget(minimum: "27.0", sdk: "27.1") }
  }

  @Test func unknownMainExecutableIsRejected() throws {
    let body = words([0x32, 24, 1, 0x000f_0500, 0x000f_0500, 0])
    var image = try MachO(words([0xfeed_facf, 0x0100_000c, 0, 2, 1, 24, 0, 0]) + body)
    #expect(throws: BuildFailure.self) { try image.validateAppStoreExecutable(patch: false) }
  }

  @Test func wideBindOffsetsSurviveLibraryRenumbering() throws {
    let build = words([0x32, 24, 1, 0x000f_0500, 0x000f_0500, 0])
    let graphics = library(
      "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics")
    let security = library("/System/Library/Frameworks/Security.framework/Versions/A/Security")
    let binding = Data([0x20, 2, 0x70] + Array(repeating: UInt8(0xff), count: 9) + [1, 0x90, 0])
    let offset = 32 + build.count + graphics.count + security.count + 48
    let bindings = words([0x22, 48, 0, 0, UInt32(offset), UInt32(binding.count), 0, 0, 0, 0, 0, 0])
    let body = build + graphics + security + bindings
    var image = try MachO(
      words([0xfeed_facf, 0x0100_000c, 0, 6, 4, UInt32(body.count), 0, 0]) + body + binding)
    try image.retarget(minimum: "27.0", sdk: "27.1")
    #expect(image.bytes[offset + 1] == 1)
    #expect(Array(image.bytes[(offset + 2)...]) == Array(binding.dropFirst(2)))
  }

  @Test func invalidVersionsDoNotOverflow() throws {
    #expect(try MachO.version("27.1") == 0x001b_0100)
    for value in ["", "27.", "27..1", "27.256", "65536.0", "-1", "27.0.0.1", "version"] {
      #expect(throws: BuildFailure.self) { try MachO.version(value) }
    }
  }

  private func library(_ path: String) -> Data {
    let string = Array(path.utf8) + [0]
    let size = (24 + string.count + 7) & ~7
    return words([0xc, UInt32(size), 24, 0, 0, 0]) + Data(string)
      + Data(repeating: 0, count: size - 24 - string.count)
  }

  private func words(_ values: [UInt32]) -> Data {
    Data(values.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
  }
}
