// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GamepadFeature",
  platforms: [.iOS("27.0"), .macOS("14.0")],
  products: [.library(name: "GamepadFeature", targets: ["GamepadFeature"])],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture.git",
      exact: "1.26.2")
  ],
  targets: [
    .target(
      name: "GamepadFeature",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]),
    .testTarget(
      name: "GamepadFeatureTests",
      dependencies: ["GamepadFeature"]),
  ],
  swiftLanguageModes: [.v6]
)
