import Foundation

func verify(_ app: URL, environment: [String: String]) throws {
  if environment["CONFIGURATION"] == "Release" {
    guard let root = environment["SRCROOT"],
      let entitlementPath = environment["CODE_SIGN_ENTITLEMENTS"]
    else {
      throw BuildFailure("Missing Release entitlement configuration")
    }
    let url =
      entitlementPath.hasPrefix("/")
      ? URL(fileURLWithPath: entitlementPath)
      : URL(fileURLWithPath: root).appending(path: entitlementPath)
    let entitlements =
      try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
      as? [String: Any] ?? [:]
    guard
      entitlements["com.apple.developer.kernel.increased-debugging-memory-limit"] as? Bool != true
    else {
      throw BuildFailure("Release cannot use the increased debugging memory entitlement")
    }
  }
  let descriptor = try Data(contentsOf: app.appending(path: "GameSupport/addonDescriptions.xml"))
  guard !descriptor.isEmpty else { throw BuildFailure("Missing App Store expansion descriptor") }
  let frameworks = app.appending(path: "Frameworks")
  let libraries = try FileManager.default.contentsOfDirectory(
    at: frameworks, includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "dylib" }.sorted { $0.path < $1.path }
  let runtime = frameworks.appending(path: "libMacShim.dylib")
  let exports = Set(
    try run("/usr/bin/nm", ["-gUj", runtime.path]).split(separator: "\n").map(String.init))
  var curl = exports.filter { $0.hasPrefix("_curl_") }
  curl.remove("_curl_easy_setopt")
  curl.insert("_Curl_vsetopt")
  curl.insert("__ZN9redgalaxy3api4UserEv")
  let native = Set(
    try run("/usr/bin/nm", ["-Uj", frameworks.appending(path: "libREDGalaxy64.dylib").path]).split(
      separator: "\n"
    ).map(String.init))
  guard curl.isSubset(of: native) else {
    throw BuildFailure("Required native CDPR entry points are missing")
  }
  var symbols = Set<String>()
  var linkedFrameworks = Set<String>()
  var linkedLibraries = Set<String>()
  let symbolPattern = try NSRegularExpression(pattern: #"external (\S+) \(from"#)
  let frameworkPattern = try NSRegularExpression(
    pattern: #"/System/Library/Frameworks/(\w+)\.framework/"#)
  for binary in [app.appending(path: "Cyberpunk2077")] + libraries {
    let owned = try MachO(Data(contentsOf: binary)).requiredRuntimeOverrides()
    let missing = owned.subtracting(exports)
    guard missing.isEmpty else {
      throw BuildFailure(
        "Runtime overrides are missing: " + missing.sorted().joined(separator: ", "))
    }
    let imports = try run("/usr/bin/nm", ["-m", "-u", binary.path])
    for line in imports.split(separator: "\n") where !line.contains("weak external") {
      let text = String(line)
      if let match = symbolPattern.firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text)
      {
        symbols.insert(String(text[range]))
      }
    }
    for line in try run("/usr/bin/otool", ["-L", binary.path]).split(separator: "\n").dropFirst() {
      let path = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " (")[0]
      if let match = frameworkPattern.firstMatch(
        in: path, range: NSRange(path.startIndex..., in: path)),
        let range = Range(match.range(at: 1), in: path)
      {
        linkedFrameworks.insert(String(path[range]))
      } else if path.hasSuffix(".dylib") {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        linkedLibraries.insert(name.hasPrefix("lib") ? String(name.dropFirst(3)) : name)
      }
    }
  }
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let response = directory.appending(path: "undefined.rsp")
  try symbols.sorted().map { "-u\n\($0)\n" }.joined().write(
    to: response, atomically: true, encoding: .utf8)
  let sdk = try run("/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-path"]).trimmingCharacters(
    in: .whitespacesAndNewlines)
  var arguments = [
    "clang", "-target", "arm64-apple-ios27.0", "-isysroot", sdk, "-dynamiclib", "-x", "c",
    "/dev/null",
    "-L" + frameworks.path, "-L" + sdk + "/usr/lib/swift", "-o",
    directory.appending(path: "verify.dylib").path,
  ]
  for name in linkedFrameworks.sorted() { arguments += ["-framework", name] }
  arguments += linkedLibraries.sorted().map { "-l" + $0 }
  arguments.append("-Wl,@" + response.path)
  _ = try run("/usr/bin/xcrun", arguments)
  print(
    "All strong imports and native CDPR entry points resolve against the bundled libraries and iOS SDK."
  )
}
