#if canImport(UIKit)
  import ComposableArchitecture
  import Combine
  import Observation
  import SwiftUI
  import UIKit

  @MainActor
  public func makeGamepadViewController(
    store: StoreOf<GamepadFeature>, client: GamepadInputClient
  ) -> UIViewController {
    GamepadViewController(store: store, client: client)
  }

  private struct ControlCircle {
    var center: CGPoint
    var radius: CGFloat

    var bounds: CGRect {
      CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    func distance(to point: CGPoint) -> CGFloat { hypot(point.x - center.x, point.y - center.y) }
  }

  private struct GamepadLayout {
    var buttons: [GamepadButton: ControlCircle] = [:]
    var toggle = ControlCircle(center: .zero, radius: 20)
    var leftStick: ControlCircle?
    var rightStick: ControlCircle?

    init(size: CGSize = .zero, insets: UIEdgeInsets = .zero) {
      guard size.width > 0, size.height > 0 else { return }
      let left = max(insets.left, 16)
      let right = size.width - max(insets.right, 16)
      let top = max(insets.top, 8)
      let bottom = size.height - max(insets.bottom, 16)
      let scale = min(1, min((right - left) / 780, (bottom - top) / 360))
      func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat = 23) -> ControlCircle {
        ControlCircle(center: CGPoint(x: x, y: y), radius: radius * scale)
      }
      let middle = size.width / 2
      buttons[.view] = circle(middle - 44 * scale, bottom - 18 * scale, 18)
      buttons[.menu] = circle(middle + 44 * scale, bottom - 18 * scale, 18)
      buttons[.pause] = circle(middle - 26 * scale, top + 22 * scale, 16)
      toggle = circle(middle + 26 * scale, top + 22 * scale, 16)
      leftStick = circle(left + 100 * scale, bottom - 92 * scale, 53)
      rightStick = circle(right - 246 * scale, bottom - 92 * scale, 53)
      let x = right - 76 * scale
      let y = bottom - 92 * scale
      buttons[.a] = circle(x, y + 50 * scale)
      buttons[.b] = circle(x + 49 * scale, y)
      buttons[.x] = circle(x - 49 * scale, y)
      buttons[.y] = circle(x, y - 50 * scale)
      buttons[.leftTrigger] = circle(left + 48 * scale, top + 26 * scale)
      buttons[.rightTrigger] = circle(right - 48 * scale, top + 26 * scale)
      buttons[.leftShoulder] = circle(left + 48 * scale, top + 88 * scale)
      buttons[.rightShoulder] = circle(right - 48 * scale, top + 88 * scale)
      buttons[.leftStick] = circle(left + 24 * scale, top + 141 * scale, 18)
      buttons[.rightStick] = circle(right - 24 * scale, top + 141 * scale, 18)
      let dpad = CGPoint(x: left + 238 * scale, y: bottom - 92 * scale)
      buttons[.dpadUp] = circle(dpad.x, dpad.y - 34 * scale, 17)
      buttons[.dpadDown] = circle(dpad.x, dpad.y + 34 * scale, 17)
      buttons[.dpadLeft] = circle(dpad.x - 34 * scale, dpad.y, 17)
      buttons[.dpadRight] = circle(dpad.x + 34 * scale, dpad.y, 17)
    }

    func path(for button: GamepadButton) -> Path {
      guard let circle = buttons[button] else { return Path() }
      func polygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        Path { path in
          path.move(
            to: CGPoint(
              x: (points[0].x + points[points.count - 1].x) / 2,
              y: (points[0].y + points[points.count - 1].y) / 2))
          for index in points.indices {
            path.addArc(
              tangent1End: points[index], tangent2End: points[(index + 1) % points.count],
              radius: radius)
          }
          path.closeSubpath()
        }
      }
      switch button {
      case .leftTrigger, .leftShoulder, .rightTrigger, .rightShoulder:
        let width = circle.radius * 3.3
        let height = circle.radius * 1.45
        var corners = [
          CGPoint(x: -width / 2, y: -height / 2),
          CGPoint(x: width / 2, y: -height / 2),
          CGPoint(x: width / 2, y: height / 2),
          CGPoint(x: -width / 2, y: height / 2),
        ]
        switch button {
        case .leftTrigger: corners[0].x += height * 0.4
        case .leftShoulder: corners[3].x += height * 0.4
        case .rightTrigger: corners[1].x -= height * 0.4
        default: corners[2].x -= height * 0.4
        }
        return polygon(corners, radius: height * 0.2).offsetBy(
          dx: circle.center.x, dy: circle.center.y)
      case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
        let angle: CGFloat
        switch button {
        case .dpadDown: angle = .pi
        case .dpadLeft: angle = -.pi / 2
        case .dpadRight: angle = .pi / 2
        default: angle = 0
        }
        return polygon(
          [
            CGPoint(x: -0.5, y: -0.5), CGPoint(x: 0.5, y: -0.5),
            CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0, y: 0.6), CGPoint(x: -0.5, y: 0.1),
          ], radius: 0.06
        ).applying(
          CGAffineTransform(translationX: circle.center.x, y: circle.center.y)
            .rotated(by: angle).scaledBy(x: circle.radius * 2, y: circle.radius * 2))
      case .view, .menu:
        return Path(
          roundedRect: circle.bounds.insetBy(dx: -circle.radius * 0.55, dy: circle.radius * 0.25),
          cornerRadius: circle.radius)
      default:
        return Path(ellipseIn: circle.bounds)
      }
    }
  }

  @Observable @MainActor
  private final class GamepadArtworkState {
    var layout = GamepadLayout()
    var input = GamepadTouchState()
    var hidden = false
    var gameplay = false
  }

  extension GamepadButton {
    fileprivate var title: String? {
      switch self {
      case .a: "A"
      case .b: "B"
      case .x: "X"
      case .y: "Y"
      case .leftShoulder: "LB"
      case .leftTrigger: "LT"
      case .rightShoulder: "RB"
      case .rightTrigger: "RT"
      case .leftStick: "L3"
      case .rightStick: "R3"
      default: nil
      }
    }

    fileprivate var symbol: String? {
      switch self {
      case .view: "rectangle.on.rectangle"
      case .menu: "line.3.horizontal"
      case .pause: "pause.fill"
      default: nil
      }
    }
  }

  private struct GamepadArtwork: View {
    var state: GamepadArtworkState
    let icons: [GamepadButton: UIImage]
    let toggle: UIImage

    var body: some View {
      Canvas { context, _ in
        if !state.hidden {
          for button in GamepadButton.allCases {
            guard let circle = state.layout.buttons[button] else { continue }
            let pressed = state.input.buttons.contains(button)
            drawControl(state.layout.path(for: button), pressed: pressed, context: &context)
            if let title = button.title {
              context.draw(
                Text(title).font(.system(size: max(12, circle.radius * 0.78), weight: .bold))
                  .foregroundStyle(.white),
                at: circle.center)
            } else if let image = icons[button] {
              let side = circle.radius
              context.draw(
                Image(uiImage: image),
                in: CGRect(
                  x: circle.center.x - side / 2, y: circle.center.y - side / 2, width: side,
                  height: side))
            }
          }
          drawStick(
            state.layout.leftStick, value: state.input.leftStick, held: state.input.leftStickHeld,
            context: &context)
          drawStick(
            state.layout.rightStick, value: state.input.rightStick,
            held: state.input.rightStickHeld, context: &context)
        }
        drawControl(Path(ellipseIn: state.layout.toggle.bounds), pressed: false, context: &context)
        let circle = state.layout.toggle
        context.draw(
          Image(uiImage: toggle),
          in: circle.bounds.insetBy(dx: circle.radius / 2, dy: circle.radius / 2))
      }
      .ignoresSafeArea()
      .accessibilityHidden(true)
    }

    private func drawControl(_ path: Path, pressed: Bool, context: inout GraphicsContext) {
      let bounds = path.boundingRect
      context.fill(path, with: .color(.black.opacity(0.38)))
      context.fill(
        path,
        with: .linearGradient(
          Gradient(stops: [
            .init(color: .white.opacity(pressed ? 0.25 : 0.12), location: 0),
            .init(color: .white.opacity(pressed ? 0.12 : 0.015), location: 0.35),
            .init(color: .white.opacity(pressed ? 0.18 : 0.055), location: 1),
          ]), startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
          endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
      context.stroke(path, with: .color(.white.opacity(pressed ? 0.7 : 0.22)), lineWidth: 1)
    }

    private func drawStick(
      _ circle: ControlCircle?, value: SIMD2<Float>, held: Bool, context: inout GraphicsContext
    ) {
      guard let circle else { return }
      let base = Path(ellipseIn: circle.bounds)
      drawControl(base, pressed: held, context: &context)
      context.fill(
        base,
        with: .radialGradient(
          Gradient(colors: [.clear, .white.opacity(held ? 0.1 : 0.045)]),
          center: circle.center, startRadius: circle.radius * 0.55, endRadius: circle.radius))
      let travel = circle.radius * 0.5
      let knob = ControlCircle(
        center: CGPoint(
          x: circle.center.x + CGFloat(value.x) * travel,
          y: circle.center.y - CGFloat(value.y) * travel),
        radius: circle.radius * 0.48)
      let path = Path(ellipseIn: knob.bounds)
      context.fill(
        path,
        with: .linearGradient(
          Gradient(colors: [.white.opacity(held ? 0.5 : 0.36), .white.opacity(held ? 0.3 : 0.21)]),
          startPoint: CGPoint(x: knob.center.x, y: knob.bounds.minY),
          endPoint: CGPoint(x: knob.center.x, y: knob.bounds.maxY)))
      context.stroke(path, with: .color(.white.opacity(held ? 0.7 : 0.3)), lineWidth: 1)
    }
  }

  @MainActor
  private final class GamepadViewController: UIViewController {
    private let store: StoreOf<GamepadFeature>
    private let client: GamepadInputClient
    private let artwork = GamepadArtworkState()
    private var surface: GamepadTouchSurface!
    private var stateObservation: AnyCancellable?
    private var layoutSize = CGSize.zero
    private var layoutInsets = UIEdgeInsets.zero

    init(store: StoreOf<GamepadFeature>, client: GamepadInputClient) {
      self.store = store
      self.client = client
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use makeGamepadViewController(store:client:)") }

    override func loadView() {
      view = GamepadPassthroughView()
      view.backgroundColor = .clear
      var icons: [GamepadButton: UIImage] = [:]
      for button in GamepadButton.allCases {
        if let symbol = button.symbol { icons[button] = Self.icon(symbol) }
      }
      let host = UIHostingController(
        rootView: GamepadArtwork(state: artwork, icons: icons, toggle: Self.icon("gamecontroller")))
      addChild(host)
      host.view.backgroundColor = .clear
      host.view.isUserInteractionEnabled = false
      host.view.frame = view.bounds
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(host.view)
      host.didMove(toParent: self)
      surface = GamepadTouchSurface(artwork: artwork, client: client) { [weak self] in
        self?.surface.reset()
        self?.store.send(.toggleControls)
      }
      surface.frame = view.bounds
      surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(surface)
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      NotificationCenter.default.addObserver(
        self, selector: #selector(deactivate), name: UIApplication.willResignActiveNotification,
        object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(activate), name: UIApplication.didBecomeActiveNotification,
        object: nil)
      stateObservation = store.publisher.sink { [weak self] _ in self?.updateState() }
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      updateLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      surface.reset()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    private func updateState() {
      let state = store.state
      if artwork.gameplay != state.isGameplay || artwork.hidden != state.controlsHidden
        || state.controllerConnected || !state.isActive
      {
        surface.reset()
      }
      artwork.gameplay = state.isGameplay
      artwork.hidden = state.controlsHidden
      surface.lookSensitivity = Float(state.lookSensitivity)
      view.isHidden = state.controllerConnected || !state.isActive
      updateLayout()
    }

    private func updateLayout() {
      let size = view.bounds.size
      let insets = view.safeAreaInsets
      guard size != layoutSize || insets != layoutInsets else { return }
      surface.reset()
      layoutSize = size
      layoutInsets = insets
      artwork.layout = GamepadLayout(size: size, insets: insets)
    }

    @objc private func deactivate() {
      surface.reset()
      store.send(.deactivate)
    }
    @objc private func activate() { store.send(.activate) }

    private static func icon(_ name: String) -> UIImage {
      guard
        let symbol = UIImage(
          systemName: name,
          withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
      else {
        preconditionFailure("Missing gamepad symbol: \(name)")
      }
      return UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in
        let scale = min(24 / symbol.size.width, 24 / symbol.size.height)
        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let rect = CGRect(
          x: (28 - size.width) / 2, y: (28 - size.height) / 2, width: size.width,
          height: size.height)
        symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: rect)
      }
    }
  }

  @MainActor
  private final class GamepadPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      let target = super.hitTest(point, with: event)
      return target === self ? nil : target
    }
  }

  @MainActor
  private final class GamepadTouchSurface: UIView {
    private let artwork: GamepadArtworkState
    private let client: GamepadInputClient
    private let toggle: () -> Void
    var lookSensitivity: Float = 1.5 {
      didSet {
        if lookSensitivity != oldValue {
          client.sendRightStick(artwork.input.rightStick(sensitivity: lookSensitivity))
        }
      }
    }

    init(artwork: GamepadArtworkState, client: GamepadInputClient, toggle: @escaping () -> Void) {
      self.artwork = artwork
      self.client = client
      self.toggle = toggle
      super.init(frame: .zero)
      backgroundColor = .clear
      isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("Use the input client initializer") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      guard !isHidden, alpha > 0, isUserInteractionEnabled else { return nil }
      return target(at: point) == nil && artwork.layout.toggle.distance(to: point) > 26 ? nil : self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      for touch in touches {
        let point = touch.location(in: self)
        if artwork.layout.toggle.distance(to: point) <= 26 {
          toggle()
          continue
        }
        guard let target = target(at: point) else { continue }
        let before = artwork.input
        if artwork.input.begin(ObjectIdentifier(touch), on: target) { move(touch) }
        publishChanges(from: before)
      }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      let before = artwork.input
      for touch in touches { move(touch) }
      publishChanges(from: before)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      let before = artwork.input
      for touch in touches { artwork.input.end(ObjectIdentifier(touch)) }
      publishChanges(from: before)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      touchesEnded(touches, with: event)
    }

    func reset() {
      let before = artwork.input
      artwork.input.reset()
      for button in before.buttons { client.sendButton(button, false) }
      client.sendLeftStick(.zero)
      client.sendRightStick(.zero)
    }

    private func target(at point: CGPoint) -> GamepadTouchState.Control? {
      guard !artwork.hidden else { return nil }
      let candidates = artwork.layout.buttons.filter {
        let path = artwork.layout.path(for: $0.key)
        let bounds = path.boundingRect
        let padding = max(7, (44 - min(bounds.width, bounds.height)) / 2)
        return path.contains(point)
          || path.strokedPath(.init(lineWidth: padding * 2)).contains(point)
      }
      if let button = candidates.min(by: {
        $0.value.distance(to: point) < $1.value.distance(to: point)
      })?.key {
        return .button(button)
      }
      if let stick = artwork.layout.leftStick, stick.distance(to: point) <= stick.radius + 14 {
        return .leftStick
      }
      if let stick = artwork.layout.rightStick, stick.distance(to: point) <= stick.radius + 14 {
        return .rightStick
      }
      return nil
    }

    private func move(_ touch: UITouch) {
      let identifier = ObjectIdentifier(touch)
      let circle: ControlCircle?
      switch artwork.input.control(for: identifier) {
      case .leftStick: circle = artwork.layout.leftStick
      case .rightStick: circle = artwork.layout.rightStick
      default: circle = nil
      }
      guard let circle else { return }
      let point = touch.location(in: self)
      artwork.input.move(
        identifier,
        displacement: SIMD2(Float(point.x - circle.center.x), Float(circle.center.y - point.y)),
        radius: Float(circle.radius))
    }

    private func publishChanges(from before: GamepadTouchState) {
      let input = artwork.input
      for button in before.buttons.subtracting(input.buttons) { client.sendButton(button, false) }
      for button in input.buttons.subtracting(before.buttons) { client.sendButton(button, true) }
      if input.leftStick != before.leftStick { client.sendLeftStick(input.leftStick) }
      if input.rightStick != before.rightStick {
        client.sendRightStick(input.rightStick(sensitivity: lookSensitivity))
      }
    }
  }
#endif
