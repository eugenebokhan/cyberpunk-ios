import Foundation
import ObjectiveC

/// Method replacement on system classes the game drives directly.
enum ObjectiveCRuntime {
  private static let mutation = NSRecursiveLock()

  /// Builds an override from the effective implementation, including inherited methods.
  @discardableResult
  static func replace(_ cls: AnyClass, _ selector: Selector, with replacement: (IMP) -> Any) -> Bool
  {
    mutation.lock()
    defer { mutation.unlock() }
    guard let method = class_getInstanceMethod(cls, selector) else { return false }
    let original = method_getImplementation(method)
    let implementation = imp_implementationWithBlock(replacement(original))
    class_replaceMethod(cls, selector, implementation, method_getTypeEncoding(method))
    return true
  }

  /// Adds a macOS-only selector without replacing an existing or inherited implementation.
  static func addIfMissing(_ cls: AnyClass, _ selector: Selector, types: String, block: Any) {
    mutation.lock()
    defer { mutation.unlock() }
    guard !class_respondsToSelector(cls, selector) else { return }
    let implementation = imp_implementationWithBlock(block)
    if !class_addMethod(cls, selector, implementation, types) {
      imp_removeBlock(implementation)
    }
  }
}
