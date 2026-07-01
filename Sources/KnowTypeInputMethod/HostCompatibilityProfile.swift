import Foundation

struct HostCompatibilityProfile: Sendable, Equatable {
    enum Carrier: Sendable, Equatable {
        case inlineComposition
        case placeholderComposition
    }

    var carrier: Carrier

    static func profile(bundleIdentifier: String?) -> HostCompatibilityProfile {
        guard let bundleIdentifier else {
            return .inline
        }
        if terminalPlaceholderBundleIDs.contains(bundleIdentifier)
            || terminalPlaceholderBundleIDPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return .terminalPlaceholder
        }
        return .inline
    }

    static let inline = HostCompatibilityProfile(
        carrier: .inlineComposition
    )

    static let terminalPlaceholder = HostCompatibilityProfile(
        carrier: .placeholderComposition
    )

    private static let terminalPlaceholderBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "org.gnu.Aquamacs",
        "org.gnu.Emacs",
        "org.vim.MacVim"
    ]

    private static let terminalPlaceholderBundleIDPrefixes = [
        "com.googlecode.iterm2"
    ]
}
