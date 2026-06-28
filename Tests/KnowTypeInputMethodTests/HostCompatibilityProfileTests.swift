import XCTest
@testable import KnowTypeInputMethod

final class HostCompatibilityProfileTests: XCTestCase {
    func testPlaceholderHostsMatchEditorAndElectronBundles() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.openai.codex"), .placeholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.dt.Xcode"), .placeholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.microsoft.VSCode"), .placeholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.electron.host"), .placeholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.jetbrains.intellij"), .placeholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.todesktop.app"), .placeholder)
    }

    func testTerminalStyleHostsMatchAsciiDefaultPlaceholderProfile() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.Terminal"), .asciiDefaultPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.googlecode.iterm2"), .asciiDefaultPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "org.vim.MacVim"), .asciiDefaultPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "org.gnu.Emacs"), .asciiDefaultPlaceholder)
        XCTAssertTrue(
            HostCompatibilityProfile
                .profile(bundleIdentifier: "com.googlecode.iterm2.helper")
                .prefersIdleAsciiPassthrough
        )
    }

    func testInlineHostsRemainDefaultForBrowsersAndUnknownClients() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.TextEdit"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.Safari"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.google.Chrome"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: nil), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.example.CustomHost"), .inline)
    }
}
