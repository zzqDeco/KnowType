import XCTest
@testable import KnowTypeSettingsApp

final class DebugInstallGuidanceTests: XCTestCase {
    func testGuidanceIncludesSeparateDiagnosticAndSelectionSteps() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "Diagnose installation" })
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "Request selection" })
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/diagnose-inputmethod.sh --strict"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh --require-selected"))
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "Request selection"
                && $0.detail.contains("Activate the text app")
                && $0.detail.contains("typing a real probe")
        })
    }

    func testGuidanceKeepsAppleDevelopmentInstallCommand() {
        XCTAssertTrue(DebugInstallGuidance.commands.contains {
            $0.contains("CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\"")
        })
    }
}
