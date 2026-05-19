import XCTest
@testable import KnowTypeSettingsUI

final class DebugInstallGuidanceTests: XCTestCase {
    func testGuidanceIncludesSeparateDiagnosticAndSelectionSteps() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "Diagnose installation" })
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "Request selection" })
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/diagnose-inputmethod.sh --strict"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/diagnose-inputmethod.sh --strict --logs"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/repair-inputmethod-selection.sh"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh --require-selected"))
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "Request selection"
                && $0.detail.contains("Activate the text app")
                && $0.detail.contains("typing a real probe")
        })
    }

    func testGuidanceExplainsSelectionRepair() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "Refresh registrar"
                && $0.detail.contains("LaunchServices")
                && $0.detail.contains("legacy .Mode")
                && $0.detail.contains(".Hans")
                && $0.detail.contains("third-party parent anchor")
        })
    }

    func testGuidanceExplainsInputMethodAuthorizationPrompt() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "Enable input source"
                && $0.detail.contains("allow")
                && $0.detail.contains("知键")
                && $0.detail.contains("KnowType")
        })
    }

    func testGuidanceKeepsAppleDevelopmentInstallCommand() {
        XCTAssertTrue(DebugInstallGuidance.commands.contains {
            $0.contains("CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\"")
        })
    }
}
