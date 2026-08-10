import Foundation
import InstallationFeature
import Testing

struct GameInstallationLayoutTests {
  private let manager = FileManager.default
  private let documents = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

  @Test func missingOrPartialGameDataIsNotReady() throws {
    defer { try? manager.removeItem(at: documents) }
    let layout = GameInstallationLayout(documents: documents)
    #expect(layout.destination.lastPathComponent == GameInstallationLayout.directoryName)
    #expect(!layout.isReady)
    for name in ["archive", "engine"] {
      try manager.createDirectory(
        at: layout.destination.appending(path: name), withIntermediateDirectories: true)
    }
    try Data().write(to: layout.destination.appending(path: "r6"))
    #expect(!layout.isReady)
  }

  @Test func incompleteHostCopyIsNotReady() throws {
    defer { try? manager.removeItem(at: documents) }
    let layout = GameInstallationLayout(documents: documents)
    for name in ["archive", "engine", "r6"] {
      try manager.createDirectory(
        at: layout.destination.appending(path: name), withIntermediateDirectories: true)
    }
    #expect(layout.isReady)
    let marker = layout.destination.appending(path: GameInstallationLayout.installationStatus)
    try Data().write(to: marker)
    #expect(!layout.isReady)
    try GameInstallationLayout.installationState(completed: false).write(
      to: marker, options: .atomic)
    #expect(!layout.isReady)
    try GameInstallationLayout.installationState(completed: true).write(
      to: marker, options: .atomic)
    #expect(layout.isReady)
  }
}
