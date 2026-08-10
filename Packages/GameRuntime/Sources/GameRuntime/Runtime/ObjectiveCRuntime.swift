import ObjectiveC

/// Method replacement on system classes the game drives directly.
enum ObjectiveCRuntime {
  /// Replaces `selector` on `cls` (overriding it there when inherited) with the block built from
  /// the implementation that was in effect. Returns false when `cls` has no such method.
  @discardableResult
  static func replace(_ cls: AnyClass, _ selector: Selector, with replacement: (IMP) -> Any) -> Bool
  {
    guard let method = class_getInstanceMethod(cls, selector) else { return false }
    let implementation = imp_implementationWithBlock(replacement(method_getImplementation(method)))
    if !class_addMethod(cls, selector, implementation, method_getTypeEncoding(method)) {
      method_setImplementation(method, implementation)
    }
    return true
  }

  /// Adds a macOS-only `selector` to `cls` when the iOS class does not implement it.
  static func addIfMissing(_ cls: AnyClass, _ selector: Selector, types: String, block: Any) {
    guard !class_respondsToSelector(cls, selector) else { return }
    class_addMethod(cls, selector, imp_implementationWithBlock(block), types)
  }
}
