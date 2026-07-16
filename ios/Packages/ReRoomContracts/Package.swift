// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ReRoomContracts",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ReRoomContracts", targets: ["ReRoomContracts"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ajevans99/swift-json-schema",
            exact: "0.13.1"
        ),
    ],
    targets: [
        .target(
            name: "ReRoomContracts",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
