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
        .library(name: "KnowTypeInputMethod", targets: ["KnowTypeInputMethod"]),
        .executable(name: "knowtype-demo", targets: ["KnowTypeDemo"])
    ],
    targets: [
        .target(
            name: "KnowTypeCore",
            path: "Sources/KnowTypeCore"
        ),
        .target(
            name: "KnowTypeProviders",
            dependencies: ["KnowTypeCore"],
            path: "Sources/KnowTypeProviders",
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "KnowTypeInputMethod",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Sources/KnowTypeInputMethod"
        ),
        .executableTarget(
            name: "KnowTypeDemo",
            dependencies: ["KnowTypeCore", "KnowTypeInputMethod"],
            path: "Sources/KnowTypeDemo"
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
