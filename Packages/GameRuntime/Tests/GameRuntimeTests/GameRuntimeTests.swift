import Foundation
import Testing

@testable import GameRuntime

@Suite struct VirtualGameBundleTests {
  let bundle = VirtualGameBundle(
    dataRoot: "/var/mobile/Documents/Cyberpunk 2077/",
    executable: "/app/Cyberpunk2077.app/Cyberpunk2077")

  @Test func reportsTheMacExecutablePathInsideTheDataRoot() {
    #expect(
      bundle.virtualExecutable
        == "/var/mobile/Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077")
  }

  @Test func mapsTheExecutableAndTheDataTree() {
    let contents = "/var/mobile/Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents"
    #expect(bundle.resolve(contents + "/MacOS/Cyberpunk2077") == bundle.executable)
    #expect(bundle.resolve(contents + "/Data") == "/var/mobile/Documents/Cyberpunk 2077")
    #expect(
      bundle.resolve(contents + "//Data/engine/config/base/general.ini")
        == "/var/mobile/Documents/Cyberpunk 2077/engine/config/base/general.ini")
  }

  @Test func leavesOtherPathsAlone() {
    let contents = "/var/mobile/Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents"
    #expect(bundle.resolve(contents + "/Resources/icon.icns") == nil)
    #expect(bundle.resolve(contents + "/MacOS") == nil)
    #expect(bundle.resolve("/var/mobile/Documents/Cyberpunk 2077/archive/pc") == nil)
    #expect(bundle.resolve("/var/mobile/Library/Saves/user.gls") == nil)
  }

  @Test func recognizesTheDataRootUnderPrivateVar() {
    #expect(bundle.dataRoot(containing: "/private/var/mobile/Documents/Cyberpunk 2077/r6") != nil)
    #expect(bundle.dataRoot(containing: "/var/mobile/Documents/Cyberpunk 2077 copy/r6") == nil)
  }

  @Test func correctsLetterCaseFromDisk() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: "archive/Mac/ep1"), withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "archive/Mac/ep1/ep1.addcont_keystone"))
    let data = VirtualGameBundle(dataRoot: root.path, executable: "")
    #expect(
      data.caseCorrected(root.path + "/archive/mac/ep1/ep1.addcont_keystone")
        == root.path + "/archive/Mac/ep1/ep1.addcont_keystone")
    #expect(data.caseCorrected(root.path + "/archive/Mac/ep1") == nil)
    #expect(data.caseCorrected(root.path + "/archive/mac/missing") == nil)
    #expect(data.caseCorrected("/tmp/archive/mac") == nil)
  }
}

@Suite struct UserSettingsDocumentTests {
  let document = """
    {"data": [{"group_name": "/video/display", "options": [
      {"name": "WindowMode", "type": "string_list", "value": "Fullscreen", "index": 0},
      {"name": "Resolution", "type": "string_list", "value": "1194x550", "default_value": "1920x1080"}
    ]}]}
    """

  @Test func replacesOnlyTheNamedValueInPlace() throws {
    let edited = try #require(
      UserSettingsDocument.settingString("Resolution", to: "1434x660", in: document))
    #expect(edited == document.replacingOccurrences(of: "\"1194x550\"", with: "\"1434x660\""))
  }

  @Test func reportsNoEditForAMatchingOrMissingOption() {
    #expect(UserSettingsDocument.settingString("Resolution", to: "1194x550", in: document) == nil)
    #expect(UserSettingsDocument.settingString("VSync", to: "Off", in: document) == nil)
  }
}

@Suite struct DisplayModeTests {
  @Test func namesResolutionsRoundedLikeTheGame() {
    let screen = CGSize(width: 956, height: 440)
    #expect(DisplayMode(index: DisplayMode.defaultIndex).settingName(screen: screen) == "1434x660")
    #expect(DisplayMode(index: 0).settingName(screen: screen) == "717x330")
    #expect(
      DisplayMode(index: 2).settingName(screen: CGSize(width: 955.9, height: 440)) == "1195x550")
  }

  @Test func outOfRangeIndicesUseTheDefaultMode() {
    #expect(DisplayMode(index: 99) == DisplayMode(index: DisplayMode.defaultIndex))
    #expect(DisplayMode(index: -1).scale == 1.5)
  }
}

@Suite struct GamePoolsTests {
  @Test func recognizesOnlyThePatchedPoolEndSite() {
    #expect(GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a0, 0xd503_201f)))
    // The unpatched site still computes the end itself: add x1, x0, x19.
    #expect(!GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a0, 0x8b13_0001)))
    #expect(!GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a1, 0xd503_201f)))
  }
}
