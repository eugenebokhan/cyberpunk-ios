// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "InstallationFeature",
  platforms: [.iOS("27.0"), .macOS("15.0")],
  products: [.library(name: "InstallationFeature", targets: ["InstallationFeature"])],
  targets: [
    .target(name: "InstallationFeature"),
    .testTarget(name: "InstallationFeatureTests", dependencies: ["InstallationFeature"]),
  ]
)
