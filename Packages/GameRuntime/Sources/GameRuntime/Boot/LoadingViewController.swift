#if os(iOS)
  import UIKit

  /// The game icon with a red spinner while the game loads. The spinner animates in the render
  /// server, so it keeps turning while the game occupies the main thread.
  final class LoadingViewController: UIViewController {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .black
      let icon = UIImageView(image: GameBoot.icon)
      icon.contentMode = .scaleAspectFit
      icon.layer.cornerRadius = 20
      icon.clipsToBounds = true
      let spinner = UIActivityIndicatorView(style: .medium)
      spinner.color = UIColor(red: 1, green: 0.13, blue: 0.2, alpha: 1)
      spinner.startAnimating()
      let stack = UIStackView(arrangedSubviews: [icon, spinner])
      stack.axis = .vertical
      stack.spacing = 28
      stack.alignment = .center
      stack.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(stack)
      NSLayoutConstraint.activate([
        icon.widthAnchor.constraint(equalToConstant: 96),
        icon.heightAnchor.constraint(equalToConstant: 96),
        stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
    }
  }
#endif
