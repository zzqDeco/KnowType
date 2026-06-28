import Foundation

struct HostCompatibilityProfile: Sendable, Equatable {
    enum Carrier: Sendable, Equatable {
        case inlineComposition
        case placeholderComposition
    }

    var carrier: Carrier
    var prefersIdleAsciiPassthrough: Bool

    static func profile(bundleIdentifier: String?) -> HostCompatibilityProfile {
        guard let bundleIdentifier else {
            return .inline
        }
        if asciiDefaultPlaceholderBundleIDs.contains(bundleIdentifier)
            || asciiDefaultPlaceholderBundleIDPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return .asciiDefaultPlaceholder
        }
        if placeholderBundleIDs.contains(bundleIdentifier)
            || placeholderBundleIDPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return .placeholder
        }
        return .inline
    }

    static let inline = HostCompatibilityProfile(
        carrier: .inlineComposition,
        prefersIdleAsciiPassthrough: false
    )

    static let placeholder = HostCompatibilityProfile(
        carrier: .placeholderComposition,
        prefersIdleAsciiPassthrough: false
    )

    static let asciiDefaultPlaceholder = HostCompatibilityProfile(
        carrier: .placeholderComposition,
        prefersIdleAsciiPassthrough: true
    )

    private static let asciiDefaultPlaceholderBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "org.gnu.Aquamacs",
        "org.gnu.Emacs",
        "org.vim.MacVim"
    ]

    private static let asciiDefaultPlaceholderBundleIDPrefixes = [
        "com.googlecode.iterm2"
    ]

    private static let placeholderBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.github.Electron",
        "com.microsoft.VSCode",
        "com.openai.codex",
        "com.visualstudio.code.oss"
    ]

    private static let placeholderBundleIDPrefixes = [
        "com.electron.",
        "com.jetbrains.",
        "com.microsoft.VSCode",
        "com.todesktop."
    ]
}
