// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KnowType",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KnowTypeCore", targets: ["KnowTypeCore"]),
        .library(name: "KnowTypeProviders", targets: ["KnowTypeProviders"]),
        .library(name: "KnowTypeInputMethod", targets: ["KnowTypeInputMethod"])
    ],
    targets: [
        .target(
            name: "KnowTypeCore",
            path: "Sources/KnowTypeCore"
        ),
        .target(
            name: "KnowTypeProviders",
            dependencies: ["KnowTypeCore"],
            path: "Sources/KnowTypeProviders"
        ),
        .target(
            name: "KnowTypeInputMethod",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Sources/KnowTypeInputMethod"
        ),
        .testTarget(
            name: "KnowTypeCoreTests",
            dependencies: ["KnowTypeCore"],
            path: "Tests/KnowTypeCoreTests"
        ),
        .testTarget(
            name: "KnowTypeProvidersTests",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Tests/KnowTypeProvidersTests"
        ),
        .testTarget(
            name: "KnowTypeInputMethodTests",
            dependencies: ["KnowTypeCore", "KnowTypeInputMethod"],
            path: "Tests/KnowTypeInputMethodTests"
        )
    ]
)
