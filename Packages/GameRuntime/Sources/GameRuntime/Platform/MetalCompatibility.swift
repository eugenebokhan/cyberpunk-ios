#if os(iOS)
  import Foundation
  import Metal
  import ObjectiveC
  import QuartzCore

  enum MetalCompatibility {
    static func install() {
      guard MTLCreateSystemDefaultDevice() != nil else {
        preconditionFailure("The game requires a Metal device.")
      }
      var count: UInt32 = 0
      guard let registered = objc_copyClassList(&count) else {
        preconditionFailure("Cannot enumerate Metal runtime classes.")
      }
      defer { free(UnsafeMutableRawPointer(registered)) }
      let classes = Array(UnsafeBufferPointer(start: registered, count: Int(count)))
      for cls in conforming("MTLDevice", among: classes) {
        adaptFactories(on: cls)
        let disabled: @convention(block) (AnyObject) -> Bool = { _ in false }
        ObjectiveCRuntime.replace(cls, #selector(getter: MTLDevice.supportsRaytracing)) { _ in
          disabled
        }
        for name in [
          "isDepth24Stencil8PixelFormatSupported", "depth24Stencil8PixelFormatSupported",
          "isHeadless", "headless", "isLowPower", "isRemovable",
        ] {
          ObjectiveCRuntime.addIfMissing(
            cls, NSSelectorFromString(name), types: "B@:", block: disabled)
        }
      }
      for cls in conforming("MTLHeap", among: classes) { adaptFactories(on: cls) }
      for cls in conforming("MTLBuffer", among: classes) {
        let sharedWrite: @convention(block) (AnyObject, NSRange) -> Void = { _, _ in }
        ObjectiveCRuntime.addIfMissing(
          cls, NSSelectorFromString("didModifyRange:"), types: "v@:{_NSRange=QQ}",
          block: sharedWrite)
      }
      for cls in conforming("MTLBlitCommandEncoder", among: classes) {
        let sharedResource: @convention(block) (AnyObject, AnyObject) -> Void = { _, _ in }
        let sharedTexture: @convention(block) (AnyObject, AnyObject, UInt, UInt) -> Void = {
          _, _, _, _ in
        }
        ObjectiveCRuntime.addIfMissing(
          cls, NSSelectorFromString("synchronizeResource:"), types: "v@:@", block: sharedResource)
        ObjectiveCRuntime.addIfMissing(
          cls, NSSelectorFromString("synchronizeTexture:slice:level:"), types: "v@:@QQ",
          block: sharedTexture)
      }
      for cls in conforming("MTLRenderCommandEncoder", among: classes) {
        let orderTextures: @convention(block) (MTLRenderCommandEncoder) -> Void = {
          $0.memoryBarrier(scope: .textures, after: .fragment, before: .fragment)
        }
        ObjectiveCRuntime.addIfMissing(
          cls, NSSelectorFromString("textureBarrier"), types: "v@:", block: orderTextures)
      }
      installPlatformSelectors()
    }

    private static func conforming(_ name: String, among classes: [AnyClass]) -> [AnyClass] {
      guard let contract = NSProtocolFromString(name) else {
        preconditionFailure("Metal does not expose the required protocol: \(name)")
      }
      let matches = classes.filter { class_conformsToProtocol($0, contract) }
      precondition(!matches.isEmpty, "Metal has no registered implementation for \(name)")
      return matches
    }

    private static func sharedOptions(_ options: UInt) -> UInt {
      let storage = UInt(MTLResourceStorageModeMask)
      return options & storage == 0x10 ? options & ~storage : options
    }

    private static func sharedDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureDescriptor
    {
      guard descriptor.storageMode.rawValue == 1 else { return descriptor }
      let copy = descriptor.copy() as! MTLTextureDescriptor
      copy.storageMode = .shared
      return copy
    }

    private static func adaptFactories(on cls: AnyClass) {
      let allocate = #selector(MTLDevice.makeBuffer(length:options:))
      ObjectiveCRuntime.replace(cls, allocate) { original in
        let call = unsafeBitCast(
          original,
          to: (@convention(c) (AnyObject, Selector, Int, UInt) -> Unmanaged<AnyObject>?).self)
        let replacement: @convention(block) (AnyObject, Int, UInt) -> Unmanaged<AnyObject>? = {
          call($0, allocate, $1, sharedOptions($2))
        }
        return replacement
      }
      let initialize = #selector(MTLDevice.makeBuffer(bytes:length:options:))
      ObjectiveCRuntime.replace(cls, initialize) { original in
        let call = unsafeBitCast(
          original,
          to: (@convention(c) (AnyObject, Selector, UnsafeRawPointer?, Int, UInt) -> Unmanaged<
            AnyObject
          >?).self)
        let replacement:
          @convention(block) (AnyObject, UnsafeRawPointer?, Int, UInt) -> Unmanaged<AnyObject>? = {
            call($0, initialize, $1, $2, sharedOptions($3))
          }
        return replacement
      }
      let texture = #selector(MTLDevice.makeTexture(descriptor:))
      ObjectiveCRuntime.replace(cls, texture) { original in
        let call = unsafeBitCast(
          original,
          to: (@convention(c) (AnyObject, Selector, MTLTextureDescriptor) -> Unmanaged<AnyObject>?)
            .self)
        let replacement:
          @convention(block) (AnyObject, MTLTextureDescriptor) -> Unmanaged<AnyObject>? = {
            call($0, texture, sharedDescriptor($1))
          }
        return replacement
      }
    }

    private static func installPlatformSelectors() {
      let synchronized: @convention(block) (AnyObject) -> Bool = { _ in true }
      let keepSynchronized: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
      ObjectiveCRuntime.addIfMissing(
        CAMetalLayer.self, NSSelectorFromString("displaySyncEnabled"), types: "B@:",
        block: synchronized)
      ObjectiveCRuntime.addIfMissing(
        CAMetalLayer.self, NSSelectorFromString("setDisplaySyncEnabled:"), types: "v@:B",
        block: keepSynchronized)
      let absentFilter: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
      ObjectiveCRuntime.addIfMissing(
        CALayer.self, NSSelectorFromString("filter"), types: "@@:", block: absentFilter)
      let user: @convention(block) (AnyObject) -> String = { _ in NSFullUserName() }
      ObjectiveCRuntime.addIfMissing(
        ProcessInfo.self, NSSelectorFromString("fullUserName"), types: "@@:", block: user)
    }
  }

  @_cdecl("MTLCopyAllDevicesWithObserver")
  public func metalCopyAllDevicesWithObserver(
    _ observer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ handler: UnsafeRawPointer?
  ) -> UnsafeMutableRawPointer {
    observer?.pointee = Unmanaged.passRetained(NSObject()).toOpaque()
    let devices = MTLCreateSystemDefaultDevice().map { [$0] } ?? []
    return Unmanaged.passRetained(devices as NSArray).toOpaque()
  }

  @_cdecl("MTLRemoveDeviceObserver")
  public func metalRemoveDeviceObserver(_ observer: UnsafeRawPointer?) {}
#endif
