#if os(iOS)
  import GameRuntimeABI
  import UIKit

  @objc(NSImage)
  public final class NSImage: NSObject {
    @objc public var size: CGSize
    final private(set) var cgImage: CGImage?
    private var focusedContext: CGContext?

    @objc public override convenience init() { self.init(size: .zero) }

    @objc(initWithSize:) public init(size: CGSize) { self.size = size }

    @objc(initWithCGImage:size:) public init(cgImage: CGImage, size: CGSize) {
      self.cgImage = cgImage
      self.size = size == .zero ? CGSize(width: cgImage.width, height: cgImage.height) : size
    }

    @objc public func lockFocus() {
      guard focusedContext == nil, size.width.isFinite, size.height.isFinite,
        let width = Int(exactly: max(1, size.width.rounded(.up))),
        let height = Int(exactly: max(1, size.height.rounded(.up))),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else {
        NSException(name: .internalInconsistencyException, reason: "cannot focus this bitmap image")
          .raise()
        return
      }
      context.scaleBy(
        x: CGFloat(width) / max(1, size.width), y: CGFloat(height) / max(1, size.height))
      if let cgImage { context.draw(cgImage, in: CGRect(origin: .zero, size: size)) }
      focusedContext = context
      UIGraphicsPushContext(context)
    }

    @objc public func unlockFocus() {
      guard let context = focusedContext else { return }
      precondition(
        UIGraphicsGetCurrentContext() === context, "image focus must be unlocked in order")
      UIGraphicsPopContext()
      cgImage = context.makeImage()
      focusedContext = nil
    }

    @objc(drawInRect:fromRect:operation:fraction:respectFlipped:hints:)
    public func draw(
      in rect: CGRect, from source: CGRect, operation: UInt, fraction: CGFloat,
      respectFlipped: Bool, hints: [String: Any]?
    ) {
      guard var pixels = cgImage, let destination = UIGraphicsGetCurrentContext() else { return }
      if !source.isEmpty {
        guard size.width > 0, size.height > 0 else { return }
        let x = CGFloat(pixels.width) / size.width
        let y = CGFloat(pixels.height) / size.height
        let pixelRect = CGRect(
          x: source.minX * x, y: (size.height - source.maxY) * y,
          width: source.width * x, height: source.height * y)
        guard let region = pixels.cropping(to: pixelRect) else { return }
        pixels = region
      }
      destination.saveGState()
      defer { destination.restoreGState() }
      destination.setAlpha(fraction)
      destination.setBlendMode(operation == 1 ? .copy : .normal)
      switch hints?[NSImageHintInterpolation as String] as? Int {
      case 1: destination.interpolationQuality = .none
      case 2: destination.interpolationQuality = .low
      case 3: destination.interpolationQuality = .high
      case 4: destination.interpolationQuality = .medium
      default: destination.interpolationQuality = .default
      }
      if respectFlipped, destination.ctm.d < 0 {
        destination.translateBy(x: 0, y: rect.minY + rect.maxY)
        destination.scaleBy(x: 1, y: -1)
      }
      destination.draw(pixels, in: rect)
    }
  }
#endif
