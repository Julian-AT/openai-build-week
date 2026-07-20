// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "SpatialCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "SpatialProtocol", targets: ["SpatialProtocol"]),
    .library(name: "CaptureCore", targets: ["CaptureCore"]),
    .library(name: "EditCore", targets: ["EditCore"]),
  ],
  targets: [
    .target(name: "SpatialProtocol"),
    .target(name: "CaptureCore", dependencies: ["SpatialProtocol"]),
    .target(name: "EditCore", dependencies: ["SpatialProtocol"]),
    .testTarget(name: "SpatialProtocolTests", dependencies: ["SpatialProtocol"]),
    .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
    .testTarget(name: "EditCoreTests", dependencies: ["EditCore"]),
  ],
  swiftLanguageModes: [.v6]
)
