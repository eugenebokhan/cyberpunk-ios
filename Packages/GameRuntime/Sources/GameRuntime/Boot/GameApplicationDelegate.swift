#if os(iOS)
  import UIKit

  /// The UIKit application and scene delegate. The scene's window shows the launcher, then the
  /// loading screen; scene activation is relayed to the game as AppKit activation.
  final class GameApplicationDelegate: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate {
    @MainActor static private(set) weak var scene: UIWindowScene?
    @MainActor static private(set) var window: UIWindow?
    var window: UIWindow?

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool { true }

    func application(
      _ application: UIApplication, configurationForConnecting session: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
      configuration.delegateClass = GameApplicationDelegate.self
      return configuration
    }

    func application(
      _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    )
      -> UIInterfaceOrientationMask
    { .landscape }

    func scene(
      _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
    ) {
      guard let scene = scene as? UIWindowScene else { return }
      Self.scene = scene
      let window = UIWindow(windowScene: scene)
      window.rootViewController = GameBoot.makeLauncher()
      window.makeKeyAndVisible()
      Self.window = window
      self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
      ScreenMetrics.refresh()
      NSApplication.shared.becomeActive(true)
    }

    func sceneWillResignActive(_ scene: UIScene) { NSApplication.shared.becomeActive(false) }

    func applicationWillTerminate(_ application: UIApplication) {
      NSApplication.shared.willTerminate()
    }
  }
#endif
