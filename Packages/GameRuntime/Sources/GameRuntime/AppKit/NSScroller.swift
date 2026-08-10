#if os(iOS)
  import UIKit

  /// A vertical AppKit scroller drawn with UIKit: its knob shows the visible proportion and the
  /// position of the scrolled content.
  @objc(NSScroller)
  public class NSScroller: NSView {
    final private var storedValue = 0.0
    final private var storedProportion = 1.0

    @objc dynamic public var doubleValue: Double {
      get { storedValue }
      set {
        storedValue = min(max(newValue, 0), 1)
        setNeedsDisplay(true)
      }
    }

    @objc dynamic public var knobProportion: Double {
      get { storedProportion }
      set {
        storedProportion = min(max(newValue, 0), 1)
        setNeedsDisplay(true)
      }
    }

    /// Parts: 1 decrement page, 2 knob, 3 increment page; anything else is the whole scroller.
    @objc(rectForPart:) dynamic public func rect(for part: Int) -> CGRect {
      let bounds = self.bounds
      let length = min(bounds.height, max(bounds.width, bounds.height * knobProportion))
      let knob = CGRect(
        x: 0, y: (bounds.height - length) * (1 - doubleValue), width: bounds.width, height: length)
      switch part {
      case 1:
        return CGRect(x: 0, y: knob.maxY, width: bounds.width, height: bounds.height - knob.maxY)
      case 2: return knob
      case 3: return CGRect(x: 0, y: 0, width: bounds.width, height: knob.minY)
      default: return bounds
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
