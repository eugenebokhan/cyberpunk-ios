import Foundation

/// The game runs its loop on the main thread and services the main run loop from its event poll,
/// so work for the main thread is scheduled on the run loop rather than the main dispatch queue.
enum MainThread {
  /// Runs `body` on the main thread and returns its result.
  static func sync<T>(_ body: @MainActor () -> T) -> T {
    var result: T?
    if Thread.isMainThread {
      MainActor.assumeIsolated { result = body() }
    } else {
      DispatchQueue.main.sync { MainActor.assumeIsolated { result = body() } }
    }
    return result!
  }

  /// Runs `body` on the main run loop's next turn.
  static func async(_ body: @escaping @MainActor () -> Void) {
    let loop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
      MainActor.assumeIsolated(body)
    }
    CFRunLoopWakeUp(loop)
  }
}
