// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ytm-cli",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ytm", targets: ["ytm"])
    ],
    dependencies: [
        .package(path: "Vendor/SwiftTUI")
    ],
    targets: [
        .target(
            name: "YTMCore",
            dependencies: []
        ),
        .target(
            name: "YTMPlayer",
            dependencies: ["YTMCore"]
        ),
        .executableTarget(
            name: "ytm",
            dependencies: [
                "YTMCore",
                "YTMPlayer",
                .product(name: "SwiftTUI", package: "SwiftTUI"),
            ]
        ),
        .testTarget(
            name: "YTMCoreTests",
            dependencies: ["YTMCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "YTMPlayerTests",
            dependencies: ["YTMPlayer"]
        ),
        .testTarget(
            name: "ytmTests",
            dependencies: ["ytm"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
