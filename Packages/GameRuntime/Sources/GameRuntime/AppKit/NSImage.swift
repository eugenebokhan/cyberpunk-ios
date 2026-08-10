#if os(iOS)
  import GameRuntimeABI
  import UIKit

  /// A bitmap image with AppKit's focus drawing: between `lockFocus` and `unlockFocus` drawing
  /// goes into the image, in AppKit's bottom-left coordinates.
  @objc(NSImage)
  public final class NSImage: NSObject {
    @objc public var size: CGSize
    final private(set) var cgImage: CGImage?
    final private var focus: CGContext?

    @objc public override convenience init() {
      self.init(size: .zero)
    }

    @objc(initWithSize:) public init(size: CGSize) {
      self.size = size
    }

    @objc(initWithCGImage:size:) public init(cgImage: CGImage, size: CGSize) {
      self.cgImage = cgImage
      self.size = size == .zero ? CGSize(width: cgImage.width, height: cgImage.height) : size
    }

    @objc public func lockFocus() {
      let width = max(1, Int(size.width.rounded(.up)))
      let height = max(1, Int(size.height.rounded(.up)))
      guard
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return }
      context.scaleBy(
        x: CGFloat(width) / max(size.width, 1), y: CGFloat(height) / max(size.height, 1))
      if let cgImage { context.draw(cgImage, in: CGRect(origin: .zero, size: size)) }
      UIGraphicsPushContext(context)
      focus = context
    }

    @objc public func unlockFocus() {
      guard let focus else { return }
      UIGraphicsPopContext()
      cgImage = focus.makeImage()
      self.focus = nil
    }

    /// Draws `source` (the whole image when empty) of the image into `rect` of the current
    /// context. Operation 1 is NSCompositingOperationCopy; the others composite over.
    @objc(drawInRect:fromRect:operation:fraction:respectFlipped:hints:)
    public func draw(
      in rect: CGRect, from source: CGRect, operation: UInt, fraction: CGFloat,
      respectFlipped: Bool,
      hints: [String: Any]?
    ) {
      guard let cgImage, let context = UIGraphicsGetCurrentContext() else { return }
      var image = cgImage
      if !source.isEmpty, size.width > 0, size.height > 0 {
        let scaleX = CGFloat(cgImage.width) / size.width
        let scaleY = CGFloat(cgImage.height) / size.height
        let pixels = CGRect(
          x: source.minX * scaleX, y: (size.height - source.maxY) * scaleY,
          width: source.width * scaleX, height: source.height * scaleY)
        guard let cropped = cgImage.cropping(to: pixels) else { return }
        image = cropped
      }
      context.saveGState()
      context.setAlpha(fraction)
      context.setBlendMode(operation == 1 ? .copy : .normal)
      // NSImageInterpolation: 1 none, 2 low, 3 high, 4 medium.
      let interpolation = hints?[NSImageHintInterpolation as String] as? Int
      context.interpolationQuality =
        [1: .none, 2: .low, 3: .high, 4: .medium][interpolation ?? 0] ?? .default
      if respectFlipped, context.ctm.d < 0 {
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
      }
      context.draw(image, in: rect)
      context.restoreGState()
    }
  }
#endif
