import Foundation

/// Replaces one option string while preserving every byte outside that JSON string.
enum UserSettingsDocument {
  private struct ObjectScope {
    let depth: Int
    var key: String?
    var fields: Set<String> = []
    var ambiguous = false
    var name: String?
    var value: Range<Int>?
  }

  /// Missing, unchanged, malformed, or ambiguous options produce no edit.
  static func settingString(_ name: String, to value: String, in text: String) -> String? {
    let data = Data(text.utf8)
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
    let bytes = Array(data)
    let decoder = JSONDecoder()
    var scopes: [ObjectScope] = []
    var matches: [Range<Int>] = []
    var depth = 0
    var index = 0

    while index < bytes.count {
      switch bytes[index] {
      case 123:  // {
        depth += 1
        scopes.append(ObjectScope(depth: depth))
      case 91:  // [
        depth += 1
      case 125:  // }
        guard let object = scopes.popLast(), object.depth == depth else { return nil }
        if !object.ambiguous, object.name == name, let range = object.value {
          matches.append(range)
        }
        depth -= 1
      case 93:  // ]
        depth -= 1
      case 34:  // "
        let start = index
        index += 1
        while index < bytes.count, bytes[index] != 34 {
          index += bytes[index] == 92 ? 2 : 1
        }
        guard index < bytes.count else { return nil }
        index += 1
        guard let current = scopes.indices.last, scopes[current].depth == depth else { continue }
        guard let string = try? decoder.decode(String.self, from: Data(bytes[start..<index])) else {
          return nil
        }
        var next = index
        while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        if next < bytes.count, bytes[next] == 58 {
          if ["name", "value"].contains(string), !scopes[current].fields.insert(string).inserted {
            scopes[current].ambiguous = true
          }
          scopes[current].key = string
        } else {
          switch scopes[current].key {
          case "name": scopes[current].name = string
          case "value": scopes[current].value = start..<index
          default: break
          }
          scopes[current].key = nil
        }
        continue
      default:
        break
      }
      index += 1
    }

    guard matches.count == 1, let range = matches.first,
      let current = try? decoder.decode(String.self, from: Data(bytes[range])), current != value,
      let replacement = try? JSONEncoder().encode(value)
    else { return nil }
    var edited = bytes
    edited.replaceSubrange(range, with: replacement)
    return String(decoding: edited, as: UTF8.self)
  }
}
