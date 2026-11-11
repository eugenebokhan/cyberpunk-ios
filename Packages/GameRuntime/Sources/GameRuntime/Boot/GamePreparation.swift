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
      if !manager.fileExists(atPath: settings.path) {
        guard
          let source = Bundle.main.url(
            forResource: "DefaultUserSettings", withExtension: "json")
        else { throw GameLaunchError.defaultSettingsMissing }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
          var initial = try JSONSerialization.jsonObject(with: Data(contentsOf: source))
            as? [String: Any],
          var groups = initial["data"] as? [[String: Any]]
        else { throw GameLaunchError.defaultSettingsMissing }
        groups.append([
          "group_name": "/video/display",
          "options": [
            [
              "name": "Resolution", "type": "string_list", "is_dynamic": true,
              "value": resolution, "index": 0,
            ]
          ],
        ])
        initial["data"] = groups
        try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
          .write(to: settings, options: .atomic)
        RuntimeLog.write("first run: iPhone graphics settings installed")
      }
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
    case gameDataMissing, contentDescriptorMissing, defaultSettingsMissing

    var errorDescription: String? {
      switch self {
      case .gameDataMissing:
        "The game data is not installed. Connect this iPhone to your Mac and install it from Xcode."
      case .contentDescriptorMissing:
        "This build is missing the App Store content descriptor. Rebuild the app from Xcode."
      case .defaultSettingsMissing:
        "This build has missing or invalid default graphics settings. Rebuild the app from Xcode."
      }
    }
  }
#endif
