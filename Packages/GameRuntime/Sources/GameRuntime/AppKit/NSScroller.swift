#if os(iOS)
  import UIKit

  @objc(NSScroller)
  public class NSScroller: NSView {
    final private var position = 0.0
    final private var proportion = 1.0

    @objc dynamic public var doubleValue: Double {
      get { MainThread.sync { position } }
      set {
        MainThread.sync {
          position = min(1, max(0, newValue))
          setNeedsDisplay(true)
        }
      }
    }

    @objc dynamic public var knobProportion: Double {
      get { MainThread.sync { proportion } }
      set {
        MainThread.sync {
          proportion = min(1, max(0, newValue))
          setNeedsDisplay(true)
        }
      }
    }

    @objc(rectForPart:) dynamic public func rect(for part: Int) -> CGRect {
      MainThread.sync {
        let extent = bounds
        let length = min(extent.height, max(extent.width, extent.height * proportion))
        let offset = isFlipped ? position : 1 - position
        let knob = CGRect(
          x: 0, y: (extent.height - length) * offset, width: extent.width, height: length)
        let before = CGRect(x: 0, y: 0, width: extent.width, height: knob.minY)
        let after = CGRect(
          x: 0, y: knob.maxY, width: extent.width, height: max(0, extent.height - knob.maxY))
        switch part {
        case 1: return isFlipped ? before : after
        case 2: return knob
        case 3: return isFlipped ? after : before
        default: return extent
        }
      }
    }

    @objc(drawRect:) dynamic public override func draw(_ dirtyRect: CGRect) {
      UIColor.clear.setFill()
      UIRectFill(dirtyRect)
      drawKnob()
    }

    @objc dynamic public func drawKnob() {
      UIColor.systemGray.setFill()
      UIBezierPath(roundedRect: rect(for: 2), cornerRadius: bounds.width / 2).fill()
    }
  }
#endif
