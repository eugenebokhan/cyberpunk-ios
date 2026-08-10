// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LauncherFeature",
  platforms: [.iOS("27.0"), .macOS("15.0")],
  products: [.library(name: "LauncherFeature", targets: ["LauncherFeature"])],
  dependencies: [
    .package(path: "../InstallationFeature"),
    .package(path: "../GamepadFeature"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
  ],
  targets: [
    .target(
      name: "LauncherFeature",
      dependencies: [
        "InstallationFeature", "GamepadFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]),
    .testTarget(name: "LauncherFeatureTests", dependencies: ["LauncherFeature"]),
  ]
)
