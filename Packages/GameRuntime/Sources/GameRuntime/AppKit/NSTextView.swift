#if os(iOS)
  import UIKit

  /// An AppKit text view backed by a UIKit text view; it grows with its text when vertically
  /// resizable and reports edits to its delegate the AppKit way.
  @objc(NSTextView)
  public final class NSTextView: NSView, UITextViewDelegate {
    private var text: UITextView!
    private var storedVerticallyResizable = false
    private var storedHorizontallyResizable = false

    @objc public weak var delegate: AnyObject?
    @objc public var minSize: CGSize
    @objc public var maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

    public override init(frame: CGRect) {
      minSize = frame.size
      super.init(frame: frame)
      text = MainThread.sync {
        let text = UITextView(frame: host.bounds)
        text.delegate = self
        text.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        text.isScrollEnabled = false
        text.textContainerInset = .zero
        text.textContainer.lineFragmentPadding = 0
        host.addSubview(text)
        return text
      }
    }

    @objc public var string: String {
      get { MainThread.sync { text.text ?? "" } }
      set {
        MainThread.sync {
          text.text = newValue
          resizeToText()
        }
      }
    }

    @objc public var verticallyResizable: Bool {
      @objc(isVerticallyResizable) get { storedVerticallyResizable }
      set {
        storedVerticallyResizable = newValue
        MainThread.sync { resizeToText() }
      }
    }

    @objc public var horizontallyResizable: Bool {
      @objc(isHorizontallyResizable) get { storedHorizontallyResizable }
      set {
        storedHorizontallyResizable = newValue
        MainThread.sync { text.textContainer.widthTracksTextView = !newValue }
      }
    }

    /// AppKit font sizes are in AppKit points.
    @objc public func setFont(_ font: UIFont) {
      MainThread.sync {
        text.font = font.withSize(font.pointSize / ScreenMetrics.appKitScale)
        resizeToText()
      }
    }

    @objc public func setTextColor(_ color: UIColor?) { MainThread.sync { text.textColor = color } }

    @objc public func setBackgroundColor(_ color: UIColor?) {
      MainThread.sync { text.backgroundColor = color }
    }

    @objc public func setInsertionPointColor(_ color: UIColor?) {
      MainThread.sync { text.tintColor = color }
    }

    @objc(insertText:replacementRange:) public func insertText(
      _ string: Any, replacementRange: NSRange
    ) {
      MainThread.sync {
        let storage = text.textStorage
        let range = replacementRange.location == NSNotFound ? text.selectedRange : replacementRange
        guard range.location <= storage.length, range.length <= storage.length - range.location
        else {
          NSException(name: .rangeException, reason: "invalid text replacement range").raise()
          return
        }
        let inserted =
          string as? NSAttributedString
          ?? NSAttributedString(string: string as? String ?? "", attributes: text.typingAttributes)
        storage.replaceCharacters(in: range, with: inserted)
        text.selectedRange = NSRange(location: range.location + inserted.length, length: 0)
        textViewDidChange(text)
      }
    }

    public func textView(
      _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
    ) -> Bool {
      let selector = Selector(("textView:shouldChangeTextInRange:replacementString:"))
      guard let delegate, delegate.responds(to: selector) else { return true }
      typealias Function =
        @convention(c) (AnyObject, Selector, AnyObject, NSRange, NSString) -> Bool
      let implementation = class_getMethodImplementation(object_getClass(delegate), selector)
      return unsafeBitCast(implementation, to: Function.self)(
        delegate, selector, self, range, text as NSString)
    }

    public func textViewDidChange(_ textView: UITextView) {
      resizeToText()
      let selector = NSSelectorFromString("textDidChange:")
      guard let delegate, delegate.responds(to: selector) else { return }
      _ = delegate.perform(
        selector,
        with: Notification(name: Notification.Name("NSTextDidChangeNotification"), object: self))
    }

    @MainActor private func resizeToText() {
      guard storedVerticallyResizable else { return }
      let fitted = text.sizeThatFits(
        CGSize(width: host.bounds.width, height: .greatestFiniteMagnitude))
      let height = min(
        maxSize.height, max(minSize.height, fitted.height * ScreenMetrics.appKitScale))
      setFrameSize(CGSize(width: frame.width, height: height))
      (superview as? NSScrollView)?.documentDidResize()
    }
  }
#endif
