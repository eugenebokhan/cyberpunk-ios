// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "GameBuildTools",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "game-build", targets: ["GameBuildTools"])],
  dependencies: [.package(path: "../InstallationFeature")],
  targets: [
    .executableTarget(name: "GameBuildTools", dependencies: ["InstallationFeature"]),
    .testTarget(name: "GameBuildToolsTests", dependencies: ["GameBuildTools"]),
  ]
)
