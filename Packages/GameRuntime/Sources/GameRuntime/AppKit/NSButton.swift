#if os(iOS)
  import UIKit

  @objc(NSButton)
  public class NSButton: NSView {
    final private var control: UIButton!
    final private weak var recipient: AnyObject?
    final private var selector: Selector?
    final private var bezel = 0

    @objc dynamic public override init(frame: CGRect) {
      super.init(frame: frame)
      MainThread.sync {
        control = UIButton(type: .system)
        control.frame = host.bounds
        control.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        control.addTarget(self, action: #selector(clicked), for: .touchUpInside)
        host.addSubview(control)
      }
    }

    @objc dynamic public var target: AnyObject? {
      get { MainThread.sync { recipient } }
      set { MainThread.sync { recipient = newValue } }
    }
    @objc dynamic public var action: Selector? {
      get { MainThread.sync { selector } }
      set { MainThread.sync { selector = newValue } }
    }
    @objc dynamic public var bezelStyle: Int {
      get { MainThread.sync { bezel } }
      set {
        MainThread.sync {
          bezel = newValue
          control.layer.cornerRadius = newValue == 1 ? 6 : 0
        }
      }
    }

    @objc dynamic public func setAttributedTitle(_ title: NSAttributedString) {
      MainThread.sync {
        let presentation = NSMutableAttributedString(attributedString: title)
        title.enumerateAttribute(.font, in: NSRange(location: 0, length: title.length)) {
          value, range, _ in
          if let font = value as? UIFont {
            presentation.addAttribute(
              .font, value: font.withSize(font.pointSize / ScreenMetrics.appKitScale), range: range)
          }
        }
        control.setAttributedTitle(presentation, for: .normal)
      }
    }

    @objc dynamic public func setBezelColor(_ color: UIColor?) {
      MainThread.sync { control.backgroundColor = color }
    }

    @objc final private func clicked() {
      MainThread.sync {
        guard let selector else { return }
        _ = NSApplication.shared.sendAction(selector, to: recipient, from: self)
      }
    }
  }
#endif
