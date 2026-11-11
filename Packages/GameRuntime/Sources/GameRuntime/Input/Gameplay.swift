import Synchronization

#if os(iOS)
  import UIKit
#endif

enum Gameplay {
  private static let state = Mutex((pointerLocked: false, cursorHides: 0))

  static var isPointerLocked: Bool { state.withLock { $0.pointerLocked } }
  static var isActive: Bool { state.withLock { $0.pointerLocked || $0.cursorHides > 0 } }

  static func setPointerLocked(_ locked: Bool) {
    guard
      state.withLock({ value in
        guard value.pointerLocked != locked else { return false }
        value.pointerLocked = locked
        return true
      })
    else { return }
    #if os(iOS)
      notifyViews()
    #endif
  }

  static func setCursorHidden(_ hidden: Bool) {
    guard
      state.withLock({ value in
        let wasActive = value.pointerLocked || value.cursorHides > 0
        if hidden {
          value.cursorHides += 1
        } else if value.cursorHides > 0 {
          value.cursorHides -= 1
        }
        return wasActive != (value.pointerLocked || value.cursorHides > 0)
      })
    else { return }
    #if os(iOS)
      notifyViews()
    #endif
  }

  #if os(iOS)
    private static func notifyViews() {
      MainThread.async {
        GamepadOverlay.shared?.setGameplay(isActive)
        for window in NSApplication.shared.windowList {
          window.uiWindow.rootViewController?.setNeedsUpdateOfPrefersPointerLocked()
        }
      }
    }
  #endif
}
