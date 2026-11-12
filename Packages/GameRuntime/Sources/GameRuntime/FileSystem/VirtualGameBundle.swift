import Foundation

/// Presents the installed data as the Mac bundle layout expected by the game.
struct VirtualGameBundle: Sendable {
  let dataRoot: String
  let executable: String
  let contents: String

  init(dataRoot: String, executable: String) {
    var root = dataRoot
    while root.count > 1, root.last == "/" { root.removeLast() }
    self.dataRoot = root
    self.executable = executable
    contents = root + "/Cyberpunk2077.app/Contents"
  }

  var virtualExecutable: String { contents + "/MacOS/Cyberpunk2077" }

  func resolve(_ path: String) -> String? {
    guard path.hasPrefix(contents + "/") else { return nil }
    let components = path.dropFirst(contents.count).split(separator: "/")
    guard let directory = components.first,
      let relative = normalized(components.dropFirst())
    else { return nil }
    switch directory {
    case "Data":
      return ([dataRoot] + relative.map(String.init)).joined(separator: "/")
    case "MacOS":
      return relative == ["Cyberpunk2077"] ? executable : nil
    default:
      return nil
    }
  }

  /// Returns a spelling correction only when every component has a unique disk match.
  func caseCorrected(
    _ path: String,
    directoryContents: (String) throws -> [String] = {
      try FileManager.default.contentsOfDirectory(atPath: $0)
    }
  ) -> String? {
    guard let root = dataRoot(containing: path),
      let components = normalized(path.dropFirst(root.count).split(separator: "/")[...])
    else { return nil }
    var result = root
    var changed = false
    for component in components {
      guard let entries = try? directoryContents(result) else {
        return nil
      }
      let requested = String(component)
      let match: String
      if entries.contains(requested) {
        match = requested
      } else {
        let matches = entries.filter { $0.caseInsensitiveCompare(requested) == .orderedSame }
        guard matches.count == 1, let found = matches.first else { return nil }
        match = found
        changed = true
      }
      result += "/" + match
    }
    return changed ? result : nil
  }

  func dataRoot(containing path: String) -> String? {
    let roots = dataRoot.hasPrefix("/var/") ? [dataRoot, "/private" + dataRoot] : [dataRoot]
    return roots.first { root in
      (path == root || path.hasPrefix(root + "/"))
        && normalized(path.dropFirst(root.count).split(separator: "/")[...]) != nil
    }
  }

  private func normalized(_ components: ArraySlice<Substring>) -> [Substring]? {
    var result: [Substring] = []
    for component in components {
      switch component {
      case ".":
        continue
      case "..":
        guard !result.isEmpty else { return nil }
        result.removeLast()
      default:
        result.append(component)
      }
    }
    return result
  }
}
