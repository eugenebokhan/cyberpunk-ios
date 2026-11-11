import Foundation

enum MainThread {
  static func sync<T>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread { return MainActor.assumeIsolated(body) }
    return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
  }

  static func async(_ body: @escaping @MainActor () -> Void) {
    let loop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
      MainActor.assumeIsolated(body)
    }
    CFRunLoopWakeUp(loop)
  }
}
