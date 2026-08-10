import Foundation

/// The Mac application layout the game derives from its executable path, backed by the iOS
/// bundle executable and the internal game-data folder.
///
/// The engine finds its data by cutting the executable path at `MacOS` and appending `Data`, so
/// `<data>/Cyberpunk2077.app/Contents/Data/...` is the game data and
/// `<data>/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077` is the executable.
struct VirtualGameBundle: Sendable {
  let dataRoot: String
  let executable: String
  let contents: String

  init(dataRoot: String, executable: String) {
    self.dataRoot = dataRoot.hasSuffix("/") ? String(dataRoot.dropLast()) : dataRoot
    self.executable = executable
    contents = self.dataRoot + "/Cyberpunk2077.app/Contents"
  }

  /// The executable path reported to the game.
  var virtualExecutable: String { contents + "/MacOS/Cyberpunk2077" }

  /// The real location of a path inside the virtual bundle, or nil for any other path.
  func resolve(_ path: String) -> String? {
    guard path.hasPrefix(contents + "/") else { return nil }
    let components = path.dropFirst(contents.count).split(separator: "/")
    if components == ["MacOS", "Cyberpunk2077"] { return executable }
    guard components.first == "Data" else { return nil }
    return ([dataRoot] + components.dropFirst().map(String.init)).joined(separator: "/")
  }

  /// A game-data path with each missing component replaced by its case-insensitive match on disk.
  /// The Mac data has `archive/Mac` where the engine asks for `archive/mac`.
  func caseCorrected(_ path: String) -> String? {
    guard let root = dataRoot(containing: path) else { return nil }
    var corrected = root
    var changed = false
    for component in path.dropFirst(root.count).split(separator: "/").map(String.init) {
      guard let names = try? FileManager.default.contentsOfDirectory(atPath: corrected),
        let match = names.contains(component)
          ? component : names.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame })
      else { return nil }
      corrected += "/" + match
      changed = changed || match != component
    }
    return changed ? corrected : nil
  }

  /// The data root spelling `path` starts with; `realpath` reports it under `/private/var`.
  func dataRoot(containing path: String) -> String? {
    let roots = dataRoot.hasPrefix("/var/") ? [dataRoot, "/private" + dataRoot] : [dataRoot]
    return roots.first { path == $0 || path.hasPrefix($0 + "/") }
  }
}
