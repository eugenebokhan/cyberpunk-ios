#if os(iOS)
  import Foundation
  import InstallationFeature

  /// What the game needs on disk before `main` runs.
  enum GamePreparation {
    /// The App Store content descriptor, which carries the expansion's store metadata, the
    /// folders the engine writes to, and the data root as the working directory.
    static func prepareData() throws {
      let layout = GameInstallationLayout.current
      guard layout.isReady else { throw GameLaunchError.gameDataMissing }
      let manager = FileManager.default
      guard
        let bundled = Bundle.main.url(
          forResource: "addonDescriptions", withExtension: "xml", subdirectory: "GameSupport"),
        let descriptor = try? Data(contentsOf: bundled), !descriptor.isEmpty
      else { throw GameLaunchError.contentDescriptorMissing }
      let destination = layout.destination.appending(
        path: "r6/publishing/mac/appstore/additional-content/addonDescriptions.xml")
      if (try? Data(contentsOf: destination)) != descriptor {
        try manager.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try descriptor.write(to: destination, options: .atomic)
        RuntimeLog.write("restored the App Store content descriptor")
      }
      for folder in ["r6/cache", "r6/config"] {
        try manager.createDirectory(
          at: layout.destination.appending(path: folder), withIntermediateDirectories: true)
      }
      guard manager.changeCurrentDirectoryPath(layout.destination.path(percentEncoded: false))
      else {
        throw GameLaunchError.gameDataMissing
      }
    }

    /// The first launch installs the bundled lowest graphics settings; every launch starts the
    /// game at the resolution chosen in the launcher.
    static func applySettings(resolution: String) throws {
      let manager = FileManager.default
      let folder = URL.applicationSupportDirectory.appending(path: "CD Projekt Red/Cyberpunk 2077")
      let settings = folder.appending(path: "UserSettings.json")
      if !manager.fileExists(atPath: settings.path(percentEncoded: false)) {
        guard
          let defaults = Bundle.main.url(forResource: "DefaultUserSettings", withExtension: "json")
        else { throw GameLaunchError.defaultSettingsMissing }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.copyItem(at: defaults, to: settings)
        RuntimeLog.write("first run: lowest graphics settings installed")
      }
      let text = try String(contentsOf: settings, encoding: .utf8)
      guard let edited = UserSettingsDocument.settingString("Resolution", to: resolution, in: text)
      else { return }
      try edited.write(to: settings, atomically: true, encoding: .utf8)
      RuntimeLog.write("start resolution \(resolution)")
    }
  }

  enum GameLaunchError: LocalizedError {
    case gameDataMissing, contentDescriptorMissing, defaultSettingsMissing

    var errorDescription: String? {
      switch self {
      case .gameDataMissing:
        "The game data is not installed. Connect this iPhone to your Mac and install it from Xcode."
      case .contentDescriptorMissing:
        "This build is missing the App Store content descriptor. Rebuild the app from Xcode."
      case .defaultSettingsMissing:
        "This build is missing its default graphics settings. Rebuild the app from Xcode."
      }
    }
  }
#endif
