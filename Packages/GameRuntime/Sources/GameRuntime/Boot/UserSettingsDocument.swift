import Foundation

/// In-place edits of the game's UserSettings.json. The engine resets a re-serialized document, so
/// values are replaced where they stand.
enum UserSettingsDocument {
  /// `text` with the string value of option `name` set to `value`, or nil when the option is
  /// missing or already has that value.
  static func settingString(_ name: String, to value: String, in text: String) -> String? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    guard let option = try? Regex("\"name\"\\s*:\\s*\"\(escaped)\""),
      let field = try? Regex("\"value\"\\s*:\\s*\"([^\"]*)\""),
      let match = text.firstMatch(of: option),
      let open = text[..<match.range.lowerBound].lastIndex(of: "{"),
      let close = text[match.range.upperBound...].firstIndex(of: "}"),
      let current = text[open...close].firstMatch(of: field),
      let range = current.output[1].range, text[range] != value
    else { return nil }
    var edited = text
    edited.replaceSubrange(range, with: value)
    return edited
  }
}
