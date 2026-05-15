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
        .executable(name: "KnowTypeSettingsApp", targets: ["KnowTypeSettingsApp"]),
        .executable(name: "KnowTypeInputMethodApp", targets: ["KnowTypeInputMethodApp"]),
        .executable(name: "knowtype-demo", targets: ["KnowTypeDemo"])
    ],
    targets: [
        .target(
            name: "KnowTypeCore",
            path: "Sources/KnowTypeCore",
            resources: [
                .process("Resources")
            ]
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
            path: "Sources/KnowTypeInputMethod",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
                .linkedFramework("InputMethodKit", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "KnowTypeSettingsApp",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Sources/KnowTypeSettingsApp",
            linkerSettings: [
                .linkedFramework("SwiftUI", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "KnowTypeInputMethodApp",
            dependencies: ["KnowTypeInputMethod"],
            path: "Sources/KnowTypeInputMethodApp",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("InputMethodKit", .when(platforms: [.macOS]))
            ]
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
            name: "KnowTypeSettingsAppTests",
            dependencies: ["KnowTypeSettingsApp", "KnowTypeProviders"],
            path: "Tests/KnowTypeSettingsAppTests"
        ),
        .testTarget(
            name: "KnowTypeInputMethodTests",
            dependencies: ["KnowTypeCore", "KnowTypeInputMethod"],
            path: "Tests/KnowTypeInputMethodTests"
        )
    ]
)
