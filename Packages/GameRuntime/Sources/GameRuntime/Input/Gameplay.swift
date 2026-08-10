#if os(iOS)
  import Synchronization
  import UIKit

  /// Whether the game is in gameplay, as it signals it: it detaches the mouse from the cursor or
  /// hides the cursor, and shows the cursor in menus. The touch gamepad switches layout with it,
  /// and game windows lock the pointer so a connected mouse reports raw motion.
  enum Gameplay {
    private static let pointerLocked = Atomic(false)
    private static let cursorHidden = Atomic(false)

    static var isPointerLocked: Bool { pointerLocked.load(ordering: .relaxed) }
    static var isActive: Bool { isPointerLocked || cursorHidden.load(ordering: .relaxed) }

    static func setPointerLocked(_ locked: Bool) {
      guard pointerLocked.exchange(locked, ordering: .relaxed) != locked else { return }
      changed()
    }

    static func setCursorHidden(_ hidden: Bool) {
      guard cursorHidden.exchange(hidden, ordering: .relaxed) != hidden else { return }
      changed()
    }

    private static func changed() {
      MainThread.async {
        GamepadOverlay.shared?.setGameplay(isActive)
        for window in NSApplication.shared.windowList {
          window.uiWindow.rootViewController?.setNeedsUpdateOfPrefersPointerLocked()
        }
      }
    }
  }
#endif
