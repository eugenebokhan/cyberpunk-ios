import CoreGraphics
import Foundation
import Synchronization

/// A render resolution offered by the launcher: a multiple of the screen size in points. The game
/// sees the chosen mode as its only display mode and as an AppKit point scale.
struct DisplayMode: Equatable, Sendable {
  static let scales: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
  /// 1.5x, e.g. 1434x660 on a 956x440 pt screen.
  static let defaultIndex = 3
  static let all = scales.indices.map(DisplayMode.init(index:))
  static let preferenceKey = "MacShimResMode2"

  private static let chosen = Mutex(
    DisplayMode(index: UserDefaults.standard.object(forKey: preferenceKey) as? Int ?? defaultIndex))

  let index: Int

  init(index: Int) {
    self.index = Self.scales.indices.contains(index) ? index : Self.defaultIndex
  }

  var scale: Double { Self.scales[index] }

  /// The size the game renders at, rounded like the game (1194.9 -> 1195).
  func pixelSize(screen: CGSize) -> (width: Int, height: Int) {
    (Int((screen.width * scale).rounded()), Int((screen.height * scale).rounded()))
  }

  /// The resolution name UserSettings.json uses, e.g. "1434x660".
  func settingName(screen: CGSize) -> String {
    let size = pixelSize(screen: screen)
    return "\(size.width)x\(size.height)"
  }

  static var selected: DisplayMode { chosen.withLock { $0 } }

  static func select(_ mode: DisplayMode) {
    UserDefaults.standard.set(mode.index, forKey: preferenceKey)
    chosen.withLock { $0 = mode }
  }
}
