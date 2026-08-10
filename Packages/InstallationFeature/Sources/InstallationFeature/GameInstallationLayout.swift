import Foundation

public struct GameInstallationLayout: Sendable {
  public static let directoryName = "Cyberpunk 2077"
  public static let installationStatus = ".installation-state"
  public let destination: URL

  public init(documents: URL) {
    destination = documents.appending(path: Self.directoryName, directoryHint: .isDirectory)
  }

  public static var current: Self { Self(documents: .documentsDirectory) }

  public static func installationState(completed: Bool) -> Data {
    Data((completed ? "ready" : "copying").utf8)
  }

  public var isReady: Bool {
    let manager = FileManager.default
    let status = destination.appending(path: Self.installationStatus)
    if manager.fileExists(atPath: status.path),
      (try? Data(contentsOf: status)) != Self.installationState(completed: true)
    {
      return false
    }
    return ["archive", "engine", "r6"].allSatisfy { name in
      var directory: ObjCBool = false
      return manager.fileExists(
        atPath: destination.appending(path: name).path, isDirectory: &directory)
        && directory.boolValue
    }
  }
}
