import Darwin
import Foundation
import MachO
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
    #expect(bundle.resolve(bundle.contents + "/MacOS/Cyberpunk2077") == bundle.executable)
    #expect(bundle.resolve(bundle.contents + "/Data") == bundle.dataRoot)
    #expect(
      bundle.resolve(bundle.contents + "//Data/engine/config/base/general.ini")
        == bundle.dataRoot + "/engine/config/base/general.ini")
  }

  @Test func leavesOtherPathsAlone() {
    #expect(bundle.resolve(bundle.contents + "/Resources/icon.icns") == nil)
    #expect(bundle.resolve(bundle.contents + "/MacOS") == nil)
    #expect(bundle.resolve(bundle.dataRoot + "/archive/pc") == nil)
    #expect(bundle.resolve("/var/mobile/Library/Saves/user.gls") == nil)
    #expect(bundle.resolve(bundle.contents + "-other/Data/archive") == nil)
  }

  @Test func normalizesWithinTheMappedSubtreeWithoutEscapingIt() {
    #expect(
      bundle.resolve(bundle.contents + "/Data/archive/../engine/./config")
        == bundle.dataRoot + "/engine/config")
    for suffix in ["/Data/../MacOS/Cyberpunk2077", "/Data/a/../../outside", "/MacOS/../../outside"]
    {
      #expect(bundle.resolve(bundle.contents + suffix) == nil)
    }
    #expect(bundle.dataRoot(containing: bundle.dataRoot + "/../Library") == nil)
  }

  @Test func recognizesTheDataRootUnderPrivateVar() {
    #expect(bundle.dataRoot(containing: "/private/var/mobile/Documents/Cyberpunk 2077/r6") != nil)
    #expect(bundle.dataRoot(containing: bundle.dataRoot + " copy/r6") == nil)
  }

  @Test func preservesUnicodeAndLiteralPercentCharacters() {
    let data = VirtualGameBundle(dataRoot: "/tmp/夜の街///", executable: "/app/game")
    #expect(data.dataRoot == "/tmp/夜の街")
    #expect(data.resolve(data.contents + "/Data/é/%2F.bin") == "/tmp/夜の街/é/%2F.bin")
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

  @Test func caseCorrectionRejectsAmbiguityAndPrefersAnExactDirectory() {
    let data = VirtualGameBundle(dataRoot: "/data", executable: "")
    let entries = [
      "/data": ["archive"], "/data/archive": ["Mac", "MAC"], "/data/archive/MAC": ["file"],
    ]
    #expect(
      data.caseCorrected("/data/archive/mac/file", directoryContents: { entries[$0] ?? [] }) == nil)
    #expect(
      data.caseCorrected("/data/archive/MAC/FILE", directoryContents: { entries[$0] ?? [] })
        == "/data/archive/MAC/file")
  }

  @Test func caseCorrectionHandlesUnicodeNames() {
    let data = VirtualGameBundle(dataRoot: "/data", executable: "")
    let entries = ["/data": ["café"], "/data/café": ["élan.bin"]]
    #expect(
      data.caseCorrected("/data/CAFÉ/ÉLAN.BIN", directoryContents: { entries[$0] ?? [] })
        == "/data/café/élan.bin")
  }

  @Test func passesNilAndUnrelatedPathBytesToTheOriginalOperation() {
    let files = GameFileSystem(bundle: bundle)
    #expect(files.withRealPath(nil, failed: { $0 < 0 }, call: { $0 == nil ? 7 : -1 }) == 7)
    let path: [CChar] = [47, -1, 0]
    path.withUnsafeBufferPointer { buffer in
      let result = files.withRealPath(buffer.baseAddress, failed: { $0 < 0 }) { pointer in
        #expect(pointer == buffer.baseAddress)
        return 8
      }
      #expect(result == 8)
    }
  }

  @Test(arguments: [ENOENT, EACCES])
  func preservesUnrelatedSystemFailures(_ error: Int32) {
    let files = GameFileSystem(bundle: bundle)
    var calls = 0
    let result = "/tmp/outside-game".withCString { path in
      files.withRealPath(path, failed: { $0 < 0 }) { _ in
        calls += 1
        errno = error
        return -1
      }
    }
    let returnedError = errno
    #expect(result == -1)
    #expect(calls == 1)
    #expect(returnedError == error)
  }

  @Test func retriesCaseMissOnceAndPreservesTheRetryError() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "Mac.bin"))
    let data = VirtualGameBundle(dataRoot: root.path, executable: "")
    let files = GameFileSystem(bundle: data)
    var calls: [String] = []
    let result = (data.contents + "/Data/mac.bin").withCString { path in
      files.withRealPath(path, failed: { $0 < 0 }) { actual in
        let actual = String(cString: actual!)
        calls.append(actual)
        errno = actual == root.path + "/Mac.bin" ? EACCES : ENOENT
        return -1
      }
    }
    let returnedError = errno
    #expect(result == -1)
    #expect(calls == [root.path + "/mac.bin", root.path + "/Mac.bin"])
    #expect(returnedError == EACCES)
  }

  @Test func executablePathReportsItsUtf8BufferRequirement() {
    let data = VirtualGameBundle(dataRoot: "/tmp/夜の街", executable: "/app/game")
    let files = GameFileSystem(bundle: data)
    var size: UInt32 = 0
    #expect(files.executablePath(into: nil, size: &size) == -1)
    #expect(Int(size) == data.virtualExecutable.utf8.count + 1)
    var buffer = [CChar](repeating: 127, count: Int(size))
    let result = buffer.withUnsafeMutableBufferPointer {
      files.executablePath(into: $0.baseAddress, size: &size)
    }
    #expect(result == 0)
    #expect(String(cString: buffer) == data.virtualExecutable)
    #expect(buffer.last == 0)
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

  @Test func editsTheDirectValueRegardlessOfPropertyOrderOrNestedMetadata() throws {
    let text =
      #"{"value":"old","metadata":{"value":"keep","description":"} { \"name\":\"Resolution\""},"name":"Resolution"}"#
    let edited = try #require(
      UserSettingsDocument.settingString("Resolution", to: "new", in: text))
    #expect(edited == text.replacingOccurrences(of: #""old""#, with: #""new""#))
  }

  @Test func matchesEscapedNamesAndWritesAValidEscapedString() throws {
    let text = #"{"name":"Resolu\u0074ion","value":"old","description":"unchanged"}"#
    let value = "夜\"\\\n"
    let edited = try #require(UserSettingsDocument.settingString("Resolution", to: value, in: text))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(edited.utf8)) as? [String: String])
    #expect(object["value"] == value)
    #expect(object["description"] == "unchanged")
    #expect(edited.hasPrefix(#"{"name":"Resolu\u0074ion","value":"#))
    #expect(edited.hasSuffix(#","description":"unchanged"}"#))
  }

  @Test func recognizesAnAlreadyMatchingEscapedValue() {
    let text = #"{"name":"Resolution","value":"1434\u0078660"}"#
    #expect(UserSettingsDocument.settingString("Resolution", to: "1434x660", in: text) == nil)
  }

  @Test(arguments: [
    #"{"name":"Resolution","value":"old""#,
    #"[{"name":"Resolution","value":"one"},{"name":"Resolution","value":"two"}]"#,
    #"{"name":"Resolution","value":["wrong"]}"#,
    #"{"name":"Resolution","value":"old","value":null}"#,
    #"{"name":"Resolution","value":"old","name":7}"#,
    #"{"description":"{\"name\":\"Resolution\",\"value\":\"old\"}","value":"keep"}"#,
  ])
  func doesNotEditMalformedAmbiguousOrUnrelatedStrings(_ text: String) {
    #expect(UserSettingsDocument.settingString("Resolution", to: "new", in: text) == nil)
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
  @Test func rollsBackTheReservationAndPreservesTheProtectionError() {
    let base = UnsafeMutableRawPointer(bitPattern: 0x1_0000_0000)!
    var released = false
    let result = GamePools.reserve(
      map: { size in
        #expect(size == GamePools.capacity + GamePools.guardSize)
        return base
      },
      protect: { address, size in
        #expect(address == base + GamePools.capacity)
        #expect(size == GamePools.guardSize)
        errno = EACCES
        return -1
      },
      release: { address, size in
        #expect(address == base)
        #expect(size == GamePools.capacity + GamePools.guardSize)
        released = true
        errno = EINVAL
        return 0
      })
    let error = errno
    #expect(result == UnsafeMutableRawPointer(bitPattern: -1))
    #expect(released)
    #expect(error == EACCES)
  }

  @Test func doesNotProtectOrReleaseAFailedMapping() {
    let failed = UnsafeMutableRawPointer(bitPattern: -1)
    let result = GamePools.reserve(
      map: { _ in
        errno = ENOMEM
        return failed
      },
      protect: { _, _ in
        Issue.record("protected a failed mapping")
        return -1
      },
      release: { _, _ in
        Issue.record("released a failed mapping")
        return -1
      })
    let error = errno
    #expect(result == failed)
    #expect(error == ENOMEM)
  }

  @Test func retainsASuccessfullyGuardedReservation() {
    let base = UnsafeMutableRawPointer(bitPattern: 0x1_0000_0000)!
    let result = GamePools.reserve(
      map: { _ in base }, protect: { _, _ in 0 },
      release: { _, _ in
        Issue.record("released a valid mapping")
        return -1
      })
    #expect(result == base)
  }

  @Test func recognizesOnlyThePatchedPoolEndSite() {
    #expect(GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a0, 0xd503_201f)))
    // The unpatched site still computes the end itself: add x1, x0, x19.
    #expect(!GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a0, 0x8b13_0001)))
    #expect(!GamePools.isPatchedPoolSite((0xb100_041f, 0x5400_00a1, 0xd503_201f)))
  }
}

@Suite struct AppKitCoordinatesTests {
  @Test func convertsPointsUsingTheViewOrientation() {
    let point = CGPoint(x: 20, y: 30)
    #expect(
      AppKitCoordinates.uiPoint(point, height: 100, flipped: false, scale: 2)
        == CGPoint(x: 10, y: 35))
    #expect(
      AppKitCoordinates.uiPoint(point, height: 100, flipped: true, scale: 2)
        == CGPoint(x: 10, y: 15))
  }

  @Test func conversionRoundTripsAcrossSupportedRenderScales() {
    let point = CGPoint(x: 37.25, y: 81.5)
    for scale: CGFloat in [0.75, 1, 1.25, 1.5, 2] {
      for flipped in [false, true] {
        let native = AppKitCoordinates.uiPoint(
          point, height: 150, flipped: flipped, scale: scale)
        let restored = AppKitCoordinates.appKitPoint(
          native, height: 150, flipped: flipped, scale: scale)
        #expect(abs(restored.x - point.x) < 0.000_001)
        #expect(abs(restored.y - point.y) < 0.000_001)
      }
    }
  }

  @Test func positionsChildrenRelativeToTheParentOrientation() {
    let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
    #expect(
      AppKitCoordinates.uiFrame(frame, parentHeight: 100, parentFlipped: false, scale: 2)
        == CGRect(x: 5, y: 20, width: 15, height: 20))
    #expect(
      AppKitCoordinates.uiFrame(frame, parentHeight: 100, parentFlipped: true, scale: 2)
        == CGRect(x: 5, y: 10, width: 15, height: 20))
  }

  @Test func convertsDirtyRectanglesWithoutChangingTheirExtent() {
    let rect = CGRect(x: 2, y: 3, width: 4, height: 5)
    #expect(
      AppKitCoordinates.appKitRect(rect, height: 100, flipped: false, scale: 2)
        == CGRect(x: 4, y: 84, width: 8, height: 10))
    #expect(
      AppKitCoordinates.appKitRect(rect, height: 100, flipped: true, scale: 2)
        == CGRect(x: 4, y: 6, width: 8, height: 10))
  }
}

@Suite struct AppKitEventQueueTests {
  @Test func frontInsertionPreservesTheRemainingEventOrder() {
    var queue = AppKitEventQueue<String>()
    queue.post("first", type: 1, atStart: false)
    queue.post("second", type: 1, atStart: false)
    queue.post("urgent", type: 1, atStart: true)
    #expect(queue.next(matching: UInt64.max, dequeue: true) == "urgent")
    #expect(queue.next(matching: UInt64.max, dequeue: true) == "first")
    #expect(queue.next(matching: UInt64.max, dequeue: true) == "second")
    #expect(queue.next(matching: UInt64.max, dequeue: true) == nil)
  }

  @Test func maskedPeekingPreservesBothTheMatchAndOtherEvents() {
    var queue = AppKitEventQueue<String>()
    queue.post("mouse", type: 1, atStart: false)
    queue.post("key", type: 10, atStart: false)
    let keyMask = UInt64(1) << 10
    #expect(queue.next(matching: keyMask, dequeue: false) == "key")
    #expect(queue.next(matching: keyMask, dequeue: false) == "key")
    #expect(queue.next(matching: UInt64.max, dequeue: true) == "mouse")
    #expect(queue.next(matching: keyMask, dequeue: true) == "key")
    #expect(queue.next(matching: UInt64.max, dequeue: true) == nil)
  }

  @Test func zeroMaskDoesNotConsumeTheHighestEventBit() {
    var queue = AppKitEventQueue<Int>()
    queue.post(42, type: 63, atStart: false)
    #expect(queue.next(matching: 0, dequeue: true) == nil)
    #expect(queue.next(matching: UInt64(1) << 63, dequeue: true) == 42)
    #expect(queue.next(matching: UInt64.max, dequeue: false) == nil)
  }
}

@Suite struct GameplayStateTests {
  @Test func nestedCursorHidesRemainActiveUntilBalanced() {
    Gameplay.setPointerLocked(false)
    defer {
      Gameplay.setCursorHidden(false)
      Gameplay.setCursorHidden(false)
      Gameplay.setPointerLocked(false)
    }
    #expect(!Gameplay.isActive)
    Gameplay.setCursorHidden(true)
    Gameplay.setCursorHidden(true)
    Gameplay.setCursorHidden(false)
    #expect(Gameplay.isActive)
    Gameplay.setCursorHidden(false)
    #expect(!Gameplay.isActive)
    Gameplay.setPointerLocked(true)
    Gameplay.setCursorHidden(true)
    Gameplay.setCursorHidden(false)
    #expect(Gameplay.isActive)
    Gameplay.setPointerLocked(false)
    #expect(!Gameplay.isActive)
  }
}

@Suite struct ControllerInputBufferTests {
  @Test func keepsButtonEdgesAheadOfCoalescedStickPositions() {
    var buffer = ControllerInputBuffer()
    buffer.append(.leftStick(SIMD2(0.2, 0.3)))
    buffer.append(.button(.a, true))
    buffer.append(.leftStick(SIMD2(0.8, -0.5)))
    buffer.append(.rightStick(SIMD2(-0.4, 0.2)))
    buffer.append(.button(.a, false))
    #expect(
      buffer.drain() == [
        .button(.a, true), .button(.a, false),
        .leftStick(SIMD2(0.8, -0.5)), .rightStick(SIMD2(-0.4, 0.2)),
      ])
    #expect(buffer.drain().isEmpty)
  }

  @Test func suppressesRepeatedStatesWithoutLosingReleaseEdges() {
    var buffer = ControllerInputBuffer()
    buffer.append(.button(.rightTrigger, true))
    buffer.append(.button(.rightTrigger, true))
    #expect(buffer.drain() == [.button(.rightTrigger, true)])
    buffer.append(.button(.rightTrigger, false))
    buffer.append(.button(.rightTrigger, false))
    #expect(buffer.drain() == [.button(.rightTrigger, false)])
    buffer.append(.leftStick(SIMD2(0.5, 0.5)))
    _ = buffer.drain()
    buffer.append(.leftStick(SIMD2(0.5, 0.5)))
    #expect(buffer.drain().isEmpty)
  }

  @Test func clampsPositionsAndNeutralizesNonfiniteInput() {
    var buffer = ControllerInputBuffer()
    buffer.append(.leftStick(SIMD2(3, -4)))
    #expect(buffer.drain() == [.leftStick(SIMD2(1, -1))])
    buffer.append(.leftStick(SIMD2(.nan, .infinity)))
    #expect(buffer.drain() == [.leftStick(.zero)])
  }

  @Test func clearingDoesNotLeaveButtonsHeld() {
    var buffer = ControllerInputBuffer()
    buffer.append(.button(.b, true))
    buffer.append(.rightStick(SIMD2(1, 1)))
    buffer.clear()
    #expect(buffer.drain().isEmpty)
    buffer.append(.button(.b, true))
    #expect(buffer.drain() == [.button(.b, true)])
  }
}

@Suite struct MainThreadTests {
  @Test @MainActor func synchronousWorkRunsInlineOnTheMainThread() {
    let marker = NSObject()
    let returned = MainThread.sync {
      #expect(Thread.isMainThread)
      return marker
    }
    #expect(returned === marker)
  }

  @Test @MainActor func backgroundCallsReturnOptionalValuesFromTheMainThread() async {
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
      DispatchQueue.global(qos: .userInteractive).async {
        let value: Int? = MainThread.sync {
          #expect(Thread.isMainThread)
          return nil
        }
        continuation.resume(returning: value)
      }
    }
    #expect(result == nil)
  }
}

@Suite struct LoadedMachOImageTests {
  @Test func validatesLoadCommandBoundaries() {
    withFixture { raw, header in
      #expect(MachOImage(header: header, slide: 0) != nil)
      header.pointee.ncmds = 2
      #expect(MachOImage(header: header, slide: 0) == nil)
      header.pointee.ncmds = 1
      raw.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)
      #expect(MachOImage(header: header, slide: 0) == nil)
      raw.storeBytes(of: UInt32(20), toByteOffset: 36, as: UInt32.self)
      #expect(MachOImage(header: header, slide: 0) == nil)
    }
  }

  @Test func readsUuidOnlyFromACompleteTypedCommand() throws {
    try withFixture { raw, header in
      let image = try #require(MachOImage(header: header, slide: 0))
      #expect(image.uuid == Array(UInt8(0)..<16))
      header.pointee.sizeofcmds = 8
      raw.storeBytes(of: UInt32(8), toByteOffset: 36, as: UInt32.self)
      let truncated = try #require(MachOImage(header: header, slide: 0))
      #expect(truncated.uuid == nil)
      #expect(truncated.entryPoint == nil)
      #expect(truncated.codeSymbols(named: ["example"]).isEmpty)
    }
  }

  @Test func rejectsAnUnsupportedLoadedHeader() {
    withFixture { _, header in
      header.pointee.cputype = CPU_TYPE_X86_64
      #expect(MachOImage(header: header, slide: 0) == nil)
      header.pointee.cputype = CPU_TYPE_ARM64
      header.pointee.magic = MH_CIGAM_64
      #expect(MachOImage(header: header, slide: 0) == nil)
    }
  }

  @Test func recognizesTheLiveTestExecutable() throws {
    let name = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    let image = try #require(MachOImage.loaded(named: name))
    #expect(image.uuid?.count == 16)
    if let entry = image.entryPoint { #expect(image.containsCode(entry)) }
    #expect(MachOImage.loaded(named: "missing-runtime-test-image") == nil)
  }

  private func withFixture(
    _ body: (UnsafeMutableRawPointer, UnsafeMutablePointer<mach_header_64>) throws -> Void
  ) rethrows {
    let raw = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
    defer { raw.deallocate() }
    var header = mach_header_64()
    header.magic = MH_MAGIC_64
    header.cputype = CPU_TYPE_ARM64
    header.filetype = UInt32(MH_EXECUTE)
    header.ncmds = 1
    header.sizeofcmds = 24
    let pointer = raw.bindMemory(to: mach_header_64.self, capacity: 1)
    pointer.initialize(to: header)
    raw.storeBytes(of: UInt32(LC_UUID), toByteOffset: 32, as: UInt32.self)
    raw.storeBytes(of: UInt32(24), toByteOffset: 36, as: UInt32.self)
    for index in 0..<16 {
      raw.storeBytes(of: UInt8(index), toByteOffset: 40 + index, as: UInt8.self)
    }
    try body(raw, pointer)
  }
}

@Suite struct ObjectiveCRuntimeTests {
  @Test func replacingAnInheritedMethodLeavesTheParentUntouched() {
    let selector = #selector(RuntimeMethodFixture.runtimeValue)
    #expect(
      ObjectiveCRuntime.replace(RuntimeInheritedFixture.self, selector) { original in
        let call = unsafeBitCast(original, to: (@convention(c) (AnyObject, Selector) -> Int).self)
        let block: @convention(block) (AnyObject) -> Int = { call($0, selector) + 5 }
        return block
      })
    #expect(RuntimeInheritedFixture().runtimeValue() == 12)
    #expect(RuntimeMethodFixture().runtimeValue() == 7)
  }

  @Test func successiveReplacementsCompose() {
    let selector = #selector(RuntimeMethodFixture.runtimeValue)
    for increment in [2, 3] {
      #expect(
        ObjectiveCRuntime.replace(RuntimeComposedFixture.self, selector) { original in
          let call = unsafeBitCast(original, to: (@convention(c) (AnyObject, Selector) -> Int).self)
          let block: @convention(block) (AnyObject) -> Int = { call($0, selector) + increment }
          return block
        })
    }
    #expect(RuntimeComposedFixture().runtimeValue() == 12)
    #expect(RuntimeMethodFixture().runtimeValue() == 7)
  }

  @Test func missingMethodsAreAddedWithoutReplacingInheritedMethods() {
    let inherited = #selector(RuntimeMethodFixture.runtimeValue)
    let replacement: @convention(block) (AnyObject) -> Int = { _ in 99 }
    ObjectiveCRuntime.addIfMissing(
      RuntimeAddedFixture.self, inherited, types: "q@:", block: replacement)
    #expect(RuntimeAddedFixture().runtimeValue() == 7)
    let added = NSSelectorFromString("runtimeAddedValue")
    ObjectiveCRuntime.addIfMissing(
      RuntimeAddedFixture.self, added, types: "q@:", block: replacement)
    let ignored: @convention(block) (AnyObject) -> Int = { _ in 42 }
    ObjectiveCRuntime.addIfMissing(RuntimeAddedFixture.self, added, types: "q@:", block: ignored)
    let instance = RuntimeAddedFixture()
    let call = unsafeBitCast(
      instance.method(for: added), to: (@convention(c) (AnyObject, Selector) -> Int).self)
    #expect(call(instance, added) == 99)
  }
}

private class RuntimeMethodFixture: NSObject {
  @objc dynamic func runtimeValue() -> Int { 7 }
}
private final class RuntimeInheritedFixture: RuntimeMethodFixture {}
private final class RuntimeComposedFixture: RuntimeMethodFixture {}
private final class RuntimeAddedFixture: RuntimeMethodFixture {}
