#if os(iOS)
  import UIKit

  /// An AppKit push button backed by a UIKit button.
  @objc(NSButton)
  public class NSButton: NSView {
    final private var button: UIButton!
    final private weak var storedTarget: AnyObject?
    final private var storedAction: Selector?
    final private var storedBezelStyle = 0

    @objc dynamic public override init(frame: CGRect) {
      super.init(frame: frame)
      button = MainThread.sync {
        let button = UIButton(type: .system)
        button.frame = host.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.addTarget(self, action: #selector(clicked), for: .touchUpInside)
        host.addSubview(button)
        return button
      }
    }

    @objc dynamic public var target: AnyObject? {
      get { storedTarget }
      set { storedTarget = newValue }
    }

    @objc dynamic public var action: Selector? {
      get { storedAction }
      set { storedAction = newValue }
    }

    /// 1 is NSBezelStyleRounded.
    @objc dynamic public var bezelStyle: Int {
      get { storedBezelStyle }
      set {
        storedBezelStyle = newValue
        MainThread.sync { button.layer.cornerRadius = newValue == 1 ? 6 : 0 }
      }
    }

    /// AppKit font sizes are in AppKit points.
    @objc dynamic public func setAttributedTitle(_ title: NSAttributedString) {
      MainThread.sync {
        let scaled = NSMutableAttributedString(attributedString: title)
        title.enumerateAttribute(.font, in: NSRange(location: 0, length: title.length)) {
          font, range, _ in
          guard let font = font as? UIFont else { return }
          scaled.addAttribute(
            .font, value: font.withSize(font.pointSize / ScreenMetrics.appKitScale), range: range)
        }
        button.setAttributedTitle(scaled, for: .normal)
      }
    }

    @objc dynamic public func setBezelColor(_ color: UIColor?) {
      MainThread.sync { button.backgroundColor = color }
    }

    @objc final private func clicked() {
      guard let target = storedTarget, let action = storedAction, target.responds(to: action) else {
        return
      }
      _ = target.perform(action, with: self)
    }
  }
#endif
