// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GameRuntime",
  platforms: [.iOS("27.0"), .macOS("15.0")],
  products: [.library(name: "GameRuntime", targets: ["GameRuntime"])],
  dependencies: [
    .package(path: "../GamepadFeature"),
    .package(path: "../InstallationFeature"),
    .package(path: "../LauncherFeature"),
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.26.2"),
  ],
  targets: [
    .target(name: "GameRuntimeABI"),
    .target(
      name: "GameRuntime",
      dependencies: [
        "GameRuntimeABI", "GamepadFeature", "InstallationFeature", "LauncherFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ],
      // The game calls in from its own threads through C and Objective-C; isolation is enforced
      // explicitly with locks, atomics and main-thread hops rather than by Swift 6 checking.
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(
      name: "GameRuntimeTests", dependencies: ["GameRuntime"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
