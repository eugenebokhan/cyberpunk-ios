import AppKit
import Foundation

@MainActor
struct MacGame {
  let app: URL
  let info: [String: Any]
  var contents: URL { app.appending(path: "Contents") }
  var data: URL { contents.appending(path: "Data") }
  var executable: URL { contents.appending(path: "MacOS/Cyberpunk2077") }
  static let libraries = [
    "libBink2MacArm64.dylib", "libGameServicesAppStore.dylib", "libREDGalaxy64.dylib",
  ]

  init() throws {
    let candidates = Set(
      NSWorkspace.shared.urlsForApplications(withBundleIdentifier: "com.cdprojektred.cyberpunk")
        .map { $0.resolvingSymlinksInPath().standardizedFileURL })
    guard candidates.count == 1, let app = candidates.first else {
      throw BuildFailure(
        candidates.isEmpty
          ? "Install Cyberpunk 2077 from the Mac App Store, then open it once before generating this project."
          : "More than one Mac App Store installation is registered. Keep one installed copy.")
    }
    self.app = app
    info =
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: app.appending(path: "Contents/Info.plist")), format: nil)
      as? [String: Any] ?? [:]
    guard info["CFBundleIdentifier"] as? String == "com.cdprojektred.cyberpunk",
      info["CFBundleShortVersionString"] as? String == "2.5.0",
      info["CFBundleVersion"] as? String == "5814786.13589799",
      let receipt = try? Data(contentsOf: contents.appending(path: "_MASReceipt/receipt")),
      !receipt.isEmpty
    else {
      throw BuildFailure(
        "The supported input is Mac App Store version 2.5.0, build 5814786.13589799")
    }
    var image = try MachO(Data(contentsOf: executable))
    guard try image.type == 2 else { throw BuildFailure("The game input is not an executable") }
    try image.validateAppStoreExecutable(patch: false)
    let actual = try FileManager.default.contentsOfDirectory(
      at: contents.appending(path: "Frameworks"), includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "dylib" }.map(\.lastPathComponent)
    guard Set(actual) == Set(Self.libraries) else {
      throw BuildFailure("Unsupported game libraries")
    }
    for directory in ["archive", "engine", "r6"] {
      guard
        (try? data.appending(path: directory).resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
          == true
      else {
        throw BuildFailure("The installed Mac game data is incomplete: \(directory)")
      }
    }
  }

  func prepare(environment: [String: String]) throws {
    func required(_ key: String) throws -> String {
      guard let value = environment[key], !value.isEmpty else {
        throw BuildFailure("Missing Xcode setting \(key)")
      }
      return value
    }
    guard environment["PLATFORM_NAME"] == "iphoneos" else {
      throw BuildFailure("Select a physical iPhone")
    }
    let root = URL(fileURLWithPath: try required("SRCROOT"))
    let destination = URL(fileURLWithPath: try required("TARGET_BUILD_DIR")).appending(
      path: try required("FULL_PRODUCT_NAME"))
    let frameworks = destination.appending(path: "Frameworks")
    let support = destination.appending(path: "GameSupport")
    let derived = URL(fileURLWithPath: try required("DERIVED_FILE_DIR"))
    for folder in [frameworks, support, derived] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    let descriptor = data.appending(
      path: "r6/publishing/mac/appstore/additional-content/addonDescriptions.xml")
    let descriptorData = try Data(contentsOf: descriptor)
    guard !descriptorData.isEmpty else {
      throw BuildFailure("Missing App Store expansion descriptor")
    }
    try descriptorData.write(to: support.appending(path: "addonDescriptions.xml"), options: .atomic)
    let minimum = try required("IPHONEOS_DEPLOYMENT_TARGET")
    let sdk = try required("SDK_VERSION")
    let executable = destination.appending(path: "Cyberpunk2077")
    try retarget(self.executable, to: executable, minimum: minimum, sdk: sdk)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let identity = environment["EXPANDED_CODE_SIGN_IDENTITY"] ?? ""
    guard environment["CODE_SIGNING_ALLOWED"] == "NO" || !identity.isEmpty else {
      throw BuildFailure("Select your signing team in Xcode")
    }
    for name in Self.libraries {
      let target = frameworks.appending(path: name)
      try retarget(
        contents.appending(path: "Frameworks/\(name)"), to: target, minimum: minimum, sdk: sdk)
      _ = try run(
        "/usr/bin/codesign", ["--force", "--sign", identity.isEmpty ? "-" : identity, target.path])
    }
    var plist =
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: root.appending(path: "Application/Info.plist")), format: nil)
      as? [String: Any] ?? [:]
    for key in ["CFBundleShortVersionString", "CFBundleVersion"] { plist[key] = info[key] }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: derived.appending(path: "GameInfo.plist"), options: .atomic)
    try writeIcon(to: destination)
    print("Prepared \(app.path), version 2.5.0")
  }

  private func writeIcon(to destination: URL) throws {
    guard let name = info["CFBundleIconFile"] as? String,
      let icon = NSImage(
        contentsOf: contents.appending(
          path: "Resources/\(name.hasSuffix(".icns") ? name : name + ".icns")"))
    else { throw BuildFailure("The Mac game's original icon is unavailable") }
    for scale in [2, 3] {
      let size = 60 * scale
      guard
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
      else { throw BuildFailure("Cannot render the original game icon") }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      context.imageInterpolation = .high
      icon.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy,
        fraction: 1)
      NSGraphicsContext.restoreGraphicsState()
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw BuildFailure("Cannot encode game icon")
      }
      try png.write(to: destination.appending(path: "AppIcon60x60@\(scale)x.png"), options: .atomic)
    }
  }
}

func retarget(_ source: URL, to target: URL, minimum: String, sdk: String) throws {
  var image = try MachO(Data(contentsOf: source))
  try image.retarget(minimum: minimum, sdk: sdk)
  try Data(image.bytes).write(to: target, options: .atomic)
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) throws -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let text = String(decoding: output, as: UTF8.self)
  guard process.terminationStatus == 0 else { throw BuildFailure("\(executable): \(text)") }
  return text
}
