#if os(iOS)
  import UIKit

  /// An AppKit scroll view backed by a UIKit scroll view, with an optional AppKit scroller that
  /// tracks and drags the content.
  @objc(NSScrollView)
  public final class NSScrollView: NSView, UIScrollViewDelegate {
    private static let scrollerWidth: CGFloat = 16
    private var scroll: UIScrollView!
    private var storedDocumentView: NSView?
    private var storedScroller: NSScroller?
    private var storedHasScroller = false
    private var storedAutohides = false
    private var storedBorderType = 0

    public override init(frame: CGRect) {
      super.init(frame: frame)
      scroll = MainThread.sync {
        let scroll = UIScrollView(frame: host.bounds)
        scroll.delegate = self
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(scroll)
        return scroll
      }
    }

    @objc public var contentSize: CGSize {
      var size = bounds.size
      if storedHasScroller, storedScroller != nil {
        size.width = max(0, size.width - Self.scrollerWidth)
      }
      return size
    }

    @objc public var documentView: NSView? {
      get { storedDocumentView }
      set {
        MainThread.sync {
          storedDocumentView?.removeFromSuperview()
          storedDocumentView = newValue
          if let newValue {
            addSubview(newValue)
            scroll.addSubview(newValue.host)
          }
          updateDocumentSize()
        }
      }
    }

    @objc public var verticalScroller: NSScroller? {
      get { storedScroller }
      set {
        MainThread.sync {
          storedScroller?.removeFromSuperview()
          storedScroller = newValue
          if let newValue {
            addSubview(newValue)
            newValue.host.addGestureRecognizer(
              UIPanGestureRecognizer(target: self, action: #selector(dragScroller)))
          }
          updateDocumentSize()
        }
      }
    }

    @objc public var hasVerticalScroller: Bool {
      get { storedHasScroller }
      set {
        storedHasScroller = newValue
        MainThread.sync { updateDocumentSize() }
      }
    }

    @objc public var autohidesScrollers: Bool {
      get { storedAutohides }
      set {
        storedAutohides = newValue
        MainThread.sync { updateDocumentSize() }
      }
    }

    /// 0 is NSNoBorder.
    @objc public var borderType: Int {
      get { storedBorderType }
      set {
        storedBorderType = newValue
        MainThread.sync {
          host.layer.borderWidth = newValue == 0 ? 0 : 1
          host.layer.borderColor = UIColor.separator.cgColor
        }
      }
    }

    /// Called by the document view when it resizes.
    func documentDidResize() { MainThread.sync { updateDocumentSize() } }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) { updateDocumentSize() }

    @MainActor private func updateDocumentSize() {
      let size = contentSize
      let scale = ScreenMetrics.appKitScale
      scroll.frame = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
      if let document = storedDocumentView {
        document.setFrameSize(CGSize(width: size.width, height: document.frame.height))
        scroll.contentSize = document.host.bounds.size
      }
      if let scroller = storedScroller {
        scroller.frame = CGRect(x: size.width, y: 0, width: Self.scrollerWidth, height: size.height)
        scroller.isHidden =
          !storedHasScroller
          || (storedAutohides && scroll.contentSize.height <= scroll.bounds.height)
        scroller.knobProportion =
          scroll.contentSize.height > 0
          ? min(1, scroll.bounds.height / scroll.contentSize.height) : 1
        let travel = scroll.contentSize.height - scroll.bounds.height
        scroller.doubleValue = travel > 0 ? scroll.contentOffset.y / travel : 0
      }
      scroll.showsVerticalScrollIndicator = storedHasScroller && storedScroller == nil
    }

    @objc private func dragScroller(_ gesture: UIPanGestureRecognizer) {
      guard let scroller = storedScroller, let view = gesture.view else { return }
      let travel = scroll.contentSize.height - scroll.bounds.height
      let barTravel = scroller.host.bounds.height * (1 - scroller.knobProportion)
      guard travel > 0, barTravel > 0 else { return }
      let offset = scroll.contentOffset.y + gesture.translation(in: view).y * travel / barTravel
      scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: min(travel, max(0, offset)))
      gesture.setTranslation(.zero, in: view)
    }
  }
#endif
