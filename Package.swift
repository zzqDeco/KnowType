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
        .library(name: "KnowTypeAI", targets: ["KnowTypeAI"]),
        .library(name: "KnowTypeSettingsUI", targets: ["KnowTypeSettingsUI"]),
        .library(name: "KnowTypeInputMethod", targets: ["KnowTypeInputMethod"]),
        .library(name: "KnowTypeInputSourceSupport", targets: ["KnowTypeInputSourceSupport"]),
        .library(name: "KnowTypePreferencePane", type: .dynamic, targets: ["KnowTypePreferencePane"]),
        .executable(name: "KnowTypeSettingsApp", targets: ["KnowTypeSettingsApp"]),
        .executable(name: "KnowTypeInputMethodApp", targets: ["KnowTypeInputMethodApp"]),
        .executable(name: "knowtype-inputsource-tool", targets: ["KnowTypeInputSourceTool"]),
        .executable(name: "knowtype-lexicon-tool", targets: ["KnowTypeLexiconTool"]),
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
            name: "KnowTypeAI",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Sources/KnowTypeAI"
        ),
        .target(
            name: "KnowTypeRimeBridge",
            path: "Sources/KnowTypeRimeBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "KnowTypeInputMethod",
            dependencies: ["KnowTypeCore", "KnowTypeProviders", "KnowTypeAI", "KnowTypeSettingsUI", "KnowTypeRimeBridge"],
            path: "Sources/KnowTypeInputMethod",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
                .linkedFramework("InputMethodKit", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "KnowTypeSettingsApp",
            dependencies: ["KnowTypeSettingsUI"],
            path: "Sources/KnowTypeSettingsApp",
            linkerSettings: [
                .linkedFramework("SwiftUI", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "KnowTypeSettingsUI",
            dependencies: ["KnowTypeCore", "KnowTypeProviders"],
            path: "Sources/KnowTypeSettingsUI",
            linkerSettings: [
                .linkedFramework("SwiftUI", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "KnowTypePreferencePane",
            dependencies: ["KnowTypeSettingsUI"],
            path: "Sources/KnowTypePreferencePane",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("PreferencePanes", .when(platforms: [.macOS])),
                .linkedFramework("SwiftUI", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "KnowTypeInputSourceSupport",
            path: "Sources/KnowTypeInputSourceSupport"
        ),
        .executableTarget(
            name: "KnowTypeInputMethodApp",
            dependencies: ["KnowTypeCore", "KnowTypeInputMethod", "KnowTypeInputSourceSupport"],
            path: "Sources/KnowTypeInputMethodApp",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("InputMethodKit", .when(platforms: [.macOS])),
                .unsafeFlags(
                    ["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"],
                    .when(platforms: [.macOS])
                )
            ]
        ),
        .executableTarget(
            name: "KnowTypeInputSourceTool",
            dependencies: ["KnowTypeInputSourceSupport"],
            path: "Sources/KnowTypeInputSourceTool",
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "KnowTypeLexiconTool",
            dependencies: ["KnowTypeCore"],
            path: "Sources/KnowTypeLexiconTool"
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
            name: "KnowTypeAITests",
            dependencies: ["KnowTypeCore", "KnowTypeProviders", "KnowTypeAI"],
            path: "Tests/KnowTypeAITests"
        ),
        .testTarget(
            name: "KnowTypeSettingsAppTests",
            dependencies: ["KnowTypeCore", "KnowTypeSettingsUI", "KnowTypeProviders"],
            path: "Tests/KnowTypeSettingsAppTests"
        ),
        .testTarget(
            name: "KnowTypeInputMethodTests",
            dependencies: ["KnowTypeCore", "KnowTypeInputMethod", "KnowTypeInputSourceSupport"],
            path: "Tests/KnowTypeInputMethodTests"
        )
    ]
)
