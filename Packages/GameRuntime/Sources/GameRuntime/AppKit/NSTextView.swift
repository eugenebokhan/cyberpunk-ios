#if os(iOS)
  import UIKit

  @objc(NSTextView)
  public final class NSTextView: NSView, UITextViewDelegate {
    private var editor: UITextView!
    private var growsVertically = false
    private var growsHorizontally = false

    @objc public weak var delegate: AnyObject?
    @objc public var minSize: CGSize
    @objc public var maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

    public override init(frame: CGRect) {
      minSize = frame.size
      super.init(frame: frame)
      MainThread.sync {
        editor = UITextView(frame: host.bounds)
        editor.delegate = self
        editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        editor.isScrollEnabled = false
        editor.textContainerInset = .zero
        editor.textContainer.lineFragmentPadding = 0
        host.addSubview(editor)
      }
    }

    @objc public override var acceptsFirstResponder: Bool { true }
    @objc public override func becomeFirstResponder() -> Bool {
      MainThread.sync { editor.becomeFirstResponder() }
    }
    @objc public override func resignFirstResponder() -> Bool {
      MainThread.sync { editor.resignFirstResponder() }
    }

    @objc public var string: String {
      get { MainThread.sync { editor.text ?? "" } }
      set {
        MainThread.sync {
          editor.text = newValue
          resizeToText()
        }
      }
    }

    @objc public var verticallyResizable: Bool {
      @objc(isVerticallyResizable) get { MainThread.sync { growsVertically } }
      set {
        MainThread.sync {
          growsVertically = newValue
          resizeToText()
        }
      }
    }
    @objc public var horizontallyResizable: Bool {
      @objc(isHorizontallyResizable) get { MainThread.sync { growsHorizontally } }
      set {
        MainThread.sync {
          growsHorizontally = newValue
          editor.textContainer.widthTracksTextView = !newValue
        }
      }
    }

    @objc public func setFont(_ font: UIFont) {
      MainThread.sync {
        editor.font = font.withSize(font.pointSize / ScreenMetrics.appKitScale)
        resizeToText()
      }
    }
    @objc public func setTextColor(_ color: UIColor?) {
      MainThread.sync { editor.textColor = color }
    }
    @objc public func setBackgroundColor(_ color: UIColor?) {
      MainThread.sync { editor.backgroundColor = color }
    }
    @objc public func setInsertionPointColor(_ color: UIColor?) {
      MainThread.sync { editor.tintColor = color }
    }

    @objc(insertText:replacementRange:) public func insertText(
      _ value: Any, replacementRange: NSRange
    ) {
      MainThread.sync {
        let inserted: NSAttributedString
        if let attributed = value as? NSAttributedString {
          inserted = attributed
        } else if let string = value as? String {
          inserted = NSAttributedString(string: string, attributes: editor.typingAttributes)
        } else {
          NSException(name: .invalidArgumentException, reason: "unsupported text insertion value")
            .raise()
          return
        }
        let storage = editor.textStorage
        let range =
          replacementRange.location == NSNotFound ? editor.selectedRange : replacementRange
        guard range.location >= 0, range.length >= 0, range.location <= storage.length,
          range.length <= storage.length - range.location
        else {
          NSException(name: .rangeException, reason: "invalid text replacement range").raise()
          return
        }
        guard textView(editor, shouldChangeTextIn: range, replacementText: inserted.string) else {
          return
        }
        storage.replaceCharacters(in: range, with: inserted)
        editor.selectedRange = NSRange(location: range.location + inserted.length, length: 0)
        textViewDidChange(editor)
      }
    }

    public func textView(
      _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
    ) -> Bool {
      let selector = NSSelectorFromString("textView:shouldChangeTextInRange:replacementString:")
      guard let delegate, delegate.responds(to: selector) else { return true }
      typealias Method =
        @convention(c) (AnyObject, Selector, AnyObject, NSRange, NSString) -> Bool
      let implementation = class_getMethodImplementation(object_getClass(delegate), selector)
      return unsafeBitCast(implementation, to: Method.self)(
        delegate, selector, self, range, replacement as NSString)
    }

    public func textViewDidChange(_ textView: UITextView) {
      resizeToText()
      let selector = NSSelectorFromString("textDidChange:")
      if let delegate, delegate.responds(to: selector) {
        let change = Notification(
          name: Notification.Name("NSTextDidChangeNotification"), object: self)
        _ = delegate.perform(selector, with: change)
      }
    }

    @MainActor private func resizeToText() {
      guard growsVertically else { return }
      let proposed = editor.sizeThatFits(
        CGSize(width: host.bounds.width, height: .greatestFiniteMagnitude))
      let height = min(
        maxSize.height, max(minSize.height, proposed.height * ScreenMetrics.appKitScale))
      setFrameSize(CGSize(width: frame.width, height: height))
      (superview as? NSScrollView)?.documentDidResize()
    }
  }
#endif
