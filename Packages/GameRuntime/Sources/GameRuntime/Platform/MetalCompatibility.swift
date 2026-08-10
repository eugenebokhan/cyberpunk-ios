#if os(iOS)
  import Foundation
  import Metal
  import QuartzCore

  /// Mac Metal usage on iOS: managed storage becomes shared (Apple GPUs share memory with the
  /// CPU, so managed synchronization has nothing to do), macOS-only queries get the answers an
  /// Apple GPU has, and ray tracing stays off because its acceleration structures count against
  /// the memory limit. MetalFX capability answers stay native.
  enum MetalCompatibility {
    private static let storageModeMask: UInt = 0xf0
    private static let managedStorage: UInt = 0x10

    static func install() {
      guard let device = MTLCreateSystemDefaultDevice(), let deviceClass = object_getClass(device)
      else {
        RuntimeLog.write("no Metal device")
        return
      }
      let rayTracing = #selector(getter: MTLDevice.supportsRaytracing)
      ObjectiveCRuntime.replace(deviceClass, rayTracing) { _ in
        let block: @convention(block) (AnyObject) -> Bool = { _ in false }
        return block
      }
      normalizeManagedStorage(on: deviceClass)
      let heapDescriptor = MTLHeapDescriptor()
      heapDescriptor.size = 1 << 16
      heapDescriptor.storageMode = .private
      if let heap = device.makeHeap(descriptor: heapDescriptor),
        let heapClass = object_getClass(heap)
      {
        normalizeManagedStorage(on: heapClass)
      }
      addMacOnlyMethods(device)
    }

    private static func shared(_ options: UInt) -> UInt {
      options & storageModeMask == managedStorage ? options & ~storageModeMask : options
    }

    private static func shared(_ descriptor: MTLTextureDescriptor) -> MTLTextureDescriptor {
      if descriptor.storageMode.rawValue == 1 { descriptor.storageMode = .shared }
      return descriptor
    }

    /// The `new...` methods return retained objects, so results pass through unmanaged.
    private static func normalizeManagedStorage(on cls: AnyClass) {
      let length = #selector(MTLDevice.makeBuffer(length:options:))
      ObjectiveCRuntime.replace(cls, length) { original in
        typealias Function =
          @convention(c) (AnyObject, Selector, Int, UInt) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(original, to: Function.self)
        let block: @convention(block) (AnyObject, Int, UInt) -> Unmanaged<AnyObject>? = {
          function($0, length, $1, shared($2))
        }
        return block
      }
      let bytes = #selector(MTLDevice.makeBuffer(bytes:length:options:))
      ObjectiveCRuntime.replace(cls, bytes) { original in
        typealias Function =
          @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Int, UInt) ->
          Unmanaged<AnyObject>?
        let function = unsafeBitCast(original, to: Function.self)
        let block:
          @convention(block) (AnyObject, UnsafeRawPointer?, Int, UInt) -> Unmanaged<AnyObject>? = {
            function($0, bytes, $1, $2, shared($3))
          }
        return block
      }
      let texture = #selector(MTLDevice.makeTexture(descriptor:))
      ObjectiveCRuntime.replace(cls, texture) { original in
        typealias Function =
          @convention(c) (AnyObject, Selector, MTLTextureDescriptor) ->
          Unmanaged<AnyObject>?
        let function = unsafeBitCast(original, to: Function.self)
        let block: @convention(block) (AnyObject, MTLTextureDescriptor) -> Unmanaged<AnyObject>? = {
          function($0, texture, shared($1))
        }
        return block
      }
    }

    private static func addMacOnlyMethods(_ device: MTLDevice) {
      let no: @convention(block) (AnyObject) -> Bool = { _ in false }
      if let deviceClass = object_getClass(device) {
        for name in [
          "isDepth24Stencil8PixelFormatSupported", "depth24Stencil8PixelFormatSupported",
          "isHeadless",
          "headless", "isLowPower", "isRemovable",
        ] {
          ObjectiveCRuntime.addIfMissing(deviceClass, Selector((name)), types: "B@:", block: no)
        }
      }
      if let buffer = device.makeBuffer(length: 16, options: .storageModeShared),
        let bufferClass = object_getClass(buffer)
      {
        let modified: @convention(block) (AnyObject, NSRange) -> Void = { _, _ in }
        ObjectiveCRuntime.addIfMissing(
          bufferClass, NSSelectorFromString("didModifyRange:"), types: "v@:{_NSRange=QQ}",
          block: modified)
      }
      guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else { return }
      if let blit = commandBuffer.makeBlitCommandEncoder(), let blitClass = object_getClass(blit) {
        let resource: @convention(block) (AnyObject, AnyObject) -> Void = { _, _ in }
        let texture: @convention(block) (AnyObject, AnyObject, UInt, UInt) -> Void = { _, _, _, _ in
        }
        ObjectiveCRuntime.addIfMissing(
          blitClass, NSSelectorFromString("synchronizeResource:"), types: "v@:@", block: resource)
        ObjectiveCRuntime.addIfMissing(
          blitClass, NSSelectorFromString("synchronizeTexture:slice:level:"), types: "v@:@QQ",
          block: texture)
        blit.endEncoding()
      }
      let target = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
      target.usage = .renderTarget
      target.storageMode = .private
      let pass = MTLRenderPassDescriptor()
      pass.colorAttachments[0].texture = device.makeTexture(descriptor: target)
      pass.colorAttachments[0].loadAction = .dontCare
      // Mac textureBarrier: order texture writes between fragment passes.
      let barrier: @convention(block) (MTLRenderCommandEncoder) -> Void = {
        $0.memoryBarrier(scope: .textures, after: .fragment, before: .fragment)
      }
      if let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
        object_getClass(render).map {
          ObjectiveCRuntime.addIfMissing(
            $0, NSSelectorFromString("textureBarrier"), types: "v@:", block: barrier)
        }
        render.endEncoding()
      }
      if let parallel = commandBuffer.makeParallelRenderCommandEncoder(descriptor: pass) {
        if let render = parallel.makeRenderCommandEncoder() {
          object_getClass(render).map {
            ObjectiveCRuntime.addIfMissing(
              $0, NSSelectorFromString("textureBarrier"), types: "v@:", block: barrier)
          }
          render.endEncoding()
        }
        parallel.endEncoding()
      }
      commandBuffer.commit()
      // iOS always synchronizes Metal presentation with the display.
      let synced: @convention(block) (AnyObject) -> Bool = { _ in true }
      let ignoreSync: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
      ObjectiveCRuntime.addIfMissing(
        CAMetalLayer.self, Selector(("displaySyncEnabled")), types: "B@:", block: synced)
      ObjectiveCRuntime.addIfMissing(
        CAMetalLayer.self, Selector(("setDisplaySyncEnabled:")), types: "v@:B", block: ignoreSync)
      let noFilter: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
      ObjectiveCRuntime.addIfMissing(
        CALayer.self, Selector(("filter")), types: "@@:", block: noFilter)
      let fullUserName: @convention(block) (AnyObject) -> String = { _ in NSFullUserName() }
      ObjectiveCRuntime.addIfMissing(
        ProcessInfo.self, Selector(("fullUserName")), types: "@@:", block: fullUserName)
    }
  }

  /// Device notifications do not exist on iOS: the one device is returned and no observer is
  /// ever called. Both results are retained, as on the Mac.
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
