#if os(iOS)
  import UIKit

  @objc(NSScrollView)
  public final class NSScrollView: NSView, UIScrollViewDelegate {
    private static let scrollerWidth: CGFloat = 16
    private var viewport: UIScrollView!
    private var pan: UIPanGestureRecognizer!
    private var document: NSView?
    private var scroller: NSScroller?
    private var scrollerEnabled = false
    private var hideUnusedScroller = false
    private var border = 0
    private var layingOut = false

    public override init(frame: CGRect) {
      super.init(frame: frame)
      MainThread.sync {
        viewport = UIScrollView(frame: host.bounds)
        viewport.delegate = self
        viewport.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewport.contentInsetAdjustmentBehavior = .never
        pan = UIPanGestureRecognizer(target: self, action: #selector(dragScroller))
        host.addSubview(viewport)
      }
    }

    @objc public var contentSize: CGSize {
      MainThread.sync {
        CGSize(
          width: max(
            0, bounds.width - (scrollerEnabled && scroller != nil ? Self.scrollerWidth : 0)),
          height: bounds.height)
      }
    }

    @objc public var documentView: NSView? {
      get { MainThread.sync { document } }
      set {
        MainThread.sync {
          guard document !== newValue else { return }
          document?.removeFromSuperview()
          document = newValue
          if let newValue {
            addSubview(newValue)
            viewport.addSubview(newValue.host)
          }
          updateDocumentSize()
        }
      }
    }

    @objc public var verticalScroller: NSScroller? {
      get { MainThread.sync { scroller } }
      set {
        MainThread.sync {
          guard scroller !== newValue else { return }
          pan.view?.removeGestureRecognizer(pan)
          scroller?.removeFromSuperview()
          scroller = newValue
          if let newValue {
            addSubview(newValue)
            newValue.host.addGestureRecognizer(pan)
          }
          updateDocumentSize()
        }
      }
    }

    @objc public var hasVerticalScroller: Bool {
      get { MainThread.sync { scrollerEnabled } }
      set {
        MainThread.sync {
          scrollerEnabled = newValue
          updateDocumentSize()
        }
      }
    }
    @objc public var autohidesScrollers: Bool {
      get { MainThread.sync { hideUnusedScroller } }
      set {
        MainThread.sync {
          hideUnusedScroller = newValue
          updateDocumentSize()
        }
      }
    }
    @objc public var borderType: Int {
      get { MainThread.sync { border } }
      set {
        MainThread.sync {
          border = newValue
          host.layer.borderWidth = newValue == 0 ? 0 : 1
          host.layer.borderColor = UIColor.separator.cgColor
        }
      }
    }

    func documentDidResize() { MainThread.sync { updateDocumentSize() } }
    public func scrollViewDidScroll(_ scrollView: UIScrollView) { updateDocumentSize() }

    @MainActor private func updateDocumentSize() {
      guard !layingOut else { return }
      layingOut = true
      defer { layingOut = false }
      let scale = ScreenMetrics.appKitScale
      let size = contentSize
      viewport.frame = CGRect(
        x: 0, y: 0, width: size.width / scale, height: size.height / scale)
      if let document {
        document.setFrameSize(CGSize(width: size.width, height: document.frame.height))
        // UIScrollView supplies the clip coordinate system around the document host.
        document.host.frame = CGRect(
          x: 0, y: 0, width: size.width / scale, height: document.frame.height / scale)
        viewport.contentSize = document.host.bounds.size
      } else {
        viewport.contentSize = .zero
        viewport.contentOffset = .zero
      }
      let travel = max(0, viewport.contentSize.height - viewport.bounds.height)
      if viewport.contentOffset.y < 0 || viewport.contentOffset.y > travel {
        viewport.contentOffset.y = min(travel, max(0, viewport.contentOffset.y))
      }
      if let scroller {
        scroller.frame = CGRect(
          x: size.width, y: 0, width: Self.scrollerWidth, height: size.height)
        scroller.isHidden = !scrollerEnabled || (hideUnusedScroller && travel == 0)
        scroller.knobProportion =
          viewport.contentSize.height > 0
          ? min(1, viewport.bounds.height / viewport.contentSize.height) : 1
        scroller.doubleValue = travel > 0 ? viewport.contentOffset.y / travel : 0
      }
      viewport.showsVerticalScrollIndicator = scrollerEnabled && scroller == nil
    }

    @objc private func dragScroller(_ gesture: UIPanGestureRecognizer) {
      guard let scroller, let view = gesture.view else { return }
      let travel = viewport.contentSize.height - viewport.bounds.height
      let knobTravel = scroller.host.bounds.height * (1 - scroller.knobProportion)
      guard travel > 0, knobTravel > 0 else { return }
      let proposed =
        viewport.contentOffset.y + gesture.translation(in: view).y * travel / knobTravel
      viewport.contentOffset.y = min(travel, max(0, proposed))
      gesture.setTranslation(.zero, in: view)
    }
  }
#endif
