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
        .library(
            name: "ReRoomCaptureCore",
            type: .static,
            targets: ["ReRoomCaptureCore"]
        ),
        .library(
            name: "ReRoomTransactionCore",
            type: .static,
            targets: ["ReRoomTransactionCore"]
        ),
        .executable(name: "ReRoomContractRunner", targets: ["ReRoomContractRunner"]),
        .executable(name: "ReRoomReplayRunner", targets: ["ReRoomReplayRunner"]),
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
        .executableTarget(
            name: "ReRoomContractRunner",
            dependencies: ["ReRoomContracts"]
        ),
        .target(
            name: "ReRoomCaptureCore",
            dependencies: ["ReRoomContracts"]
        ),
        .target(
            name: "ReRoomTransactionCore",
            dependencies: ["ReRoomContracts", "ReRoomCaptureCore"]
        ),
        .executableTarget(
            name: "ReRoomReplayRunner",
            dependencies: ["ReRoomCaptureCore"]
        ),
        .testTarget(
            name: "ReRoomContractsTests",
            dependencies: ["ReRoomContracts"]
        ),
        .testTarget(
            name: "ReRoomCaptureCoreTests",
            dependencies: ["ReRoomCaptureCore"]
        ),
        .testTarget(
            name: "ReRoomReplayRunnerTests",
            dependencies: ["ReRoomCaptureCore"]
        ),
        .testTarget(
            name: "ReRoomTransactionCoreTests",
            dependencies: ["ReRoomContracts", "ReRoomTransactionCore"]
        ),
        .testTarget(
            name: "ReRoomTransactionTraceExporterTests",
            dependencies: ["ReRoomContracts", "ReRoomTransactionCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
