import XCTest
@testable import KnowTypeInputMethod

final class HostCompatibilityProfileTests: XCTestCase {
    func testCodeEditorAndElectronHostsDefaultToInlineCarrier() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.openai.codex"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.dt.Xcode"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.microsoft.VSCode"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.visualstudio.code.oss"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.electron.host"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.jetbrains.intellij"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.todesktop.app"), .inline)
    }

    func testTerminalStyleHostsMatchPlaceholderCarrierProfile() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.Terminal"), .terminalPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.googlecode.iterm2"), .terminalPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "org.vim.MacVim"), .terminalPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "org.gnu.Emacs"), .terminalPlaceholder)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.googlecode.iterm2.helper"), .terminalPlaceholder)
    }

    func testInlineHostsRemainDefaultForBrowsersAndUnknownClients() {
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.TextEdit"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.apple.Safari"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.google.Chrome"), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: nil), .inline)
        XCTAssertEqual(HostCompatibilityProfile.profile(bundleIdentifier: "com.example.CustomHost"), .inline)
    }
}
