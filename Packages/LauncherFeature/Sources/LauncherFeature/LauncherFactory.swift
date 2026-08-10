#if canImport(UIKit)
  import ComposableArchitecture
  import SwiftUI
  import UIKit

  @MainActor
  public func makeLauncherViewController(
    resolutions: [String], selectedResolution: Int, icon: UIImage, client: LauncherClient
  ) -> UIViewController {
    let store = Store(
      initialState: LauncherFeature.State(
        resolutions: resolutions, resolution: selectedResolution)
    ) {
      LauncherFeature(client: client)
    }
    return LauncherHostingController(rootView: LauncherView(store: store, icon: icon))
  }

  private final class LauncherHostingController: UIHostingController<LauncherView> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
  }
#endif
