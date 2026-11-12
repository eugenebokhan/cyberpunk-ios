#if os(iOS)
  import Darwin
  import Foundation
  import InstallationFeature

  enum GamePreparation {
    static func prepareData() throws {
      let layout = GameInstallationLayout.current
      guard layout.isReady else { throw GameLaunchError.gameDataMissing }
      guard
        let source = Bundle.main.url(
          forResource: "addonDescriptions", withExtension: "xml", subdirectory: "GameSupport")
      else { throw GameLaunchError.contentDescriptorMissing }
      let descriptor = try Data(contentsOf: source)
      guard !descriptor.isEmpty else { throw GameLaunchError.contentDescriptorMissing }

      let manager = FileManager.default
      let destination = layout.destination.appending(
        path: "r6/publishing/mac/appstore/additional-content/addonDescriptions.xml")
      if manager.contents(atPath: destination.path) != descriptor {
        try manager.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try descriptor.write(to: destination, options: .atomic)
        RuntimeLog.write("restored the App Store content descriptor")
      }
      for folder in ["r6/cache", "r6/config"] {
        try manager.createDirectory(
          at: layout.destination.appending(path: folder), withIntermediateDirectories: true)
      }
      let path = layout.destination.path(percentEncoded: false)
      guard chdir(path) == 0 else {
        throw NSError(
          domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
      }
    }

    static func applySettings(resolution: String) throws {
      let manager = FileManager.default
      let directory = URL.applicationSupportDirectory.appending(
        path: "CD Projekt Red/Cyberpunk 2077")
      let settings = directory.appending(path: "UserSettings.json")
      guard manager.fileExists(atPath: settings.path) else { return }
      let original = try String(contentsOf: settings, encoding: .utf8)
      if let updated = UserSettingsDocument.settingString(
        "Resolution", to: resolution, in: original)
      {
        try updated.write(to: settings, atomically: true, encoding: .utf8)
        RuntimeLog.write("start resolution \(resolution)")
      }
    }
  }

  enum GameLaunchError: LocalizedError {
    case gameDataMissing, contentDescriptorMissing

    var errorDescription: String? {
      switch self {
      case .gameDataMissing:
        "The game data is not installed. Connect this iPhone to your Mac and install it from Xcode."
      case .contentDescriptorMissing:
        "This build is missing the App Store content descriptor. Rebuild the app from Xcode."
      }
    }
  }
#endif
