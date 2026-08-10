import Foundation
import InstallationFeature

@main
@MainActor
struct GameBuildTool {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      switch arguments.first {
      case "prepare": try MacGame().prepare(environment: ProcessInfo.processInfo.environment)
      case "locate": print(try MacGame().app.path)
      case "verify" where arguments.count == 2:
        try verify(
          URL(fileURLWithPath: arguments[1]), environment: ProcessInfo.processInfo.environment)
      case "install-data" where (2...3).contains(arguments.count):
        try installData(
          device: arguments[1],
          bundle: arguments.count == 3 ? arguments[2] : "com.eugenebokhan.cyport")
      case "retarget" where arguments.count == 5:
        try retarget(
          URL(fileURLWithPath: arguments[1]), to: URL(fileURLWithPath: arguments[2]),
          minimum: arguments[3], sdk: arguments[4])
      default:
        throw BuildFailure(
          "Usage: game-build prepare | locate | verify APP | install-data DEVICE [BUNDLE] | retarget IN OUT MINIMUM SDK"
        )
      }
    } catch {
      FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func installData(device: String, bundle: String) throws {
    let source = try MacGame().data
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appending(path: UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let status = temporary.appending(path: GameInstallationLayout.installationStatus)
    let destination = "Documents/\(GameInstallationLayout.directoryName)"
    func copy(_ source: URL, to destination: String) throws {
      print("Transferring \(source.lastPathComponent)…")
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = [
        "devicectl", "device", "copy", "to", "--device", device,
        "--domain-type", "appDataContainer", "--domain-identifier", bundle,
        "--source", source.path, "--destination", destination,
      ]
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw BuildFailure(
          "Game data transfer stopped. Reconnect the iPhone and run again to resume.")
      }
    }
    try GameInstallationLayout.installationState(completed: false).write(
      to: status, options: .atomic)
    try copy(temporary, to: destination)
    try copy(source, to: destination)
    try GameInstallationLayout.installationState(completed: true).write(
      to: status, options: .atomic)
    try copy(status, to: "\(destination)/\(GameInstallationLayout.installationStatus)")
    print("Game data is ready. Saves and CDPR credentials were preserved.")
  }
}
