import XCTest
@testable import KnowTypeSettingsUI

final class DebugInstallGuidanceTests: XCTestCase {
    func testGuidanceIncludesSeparateDiagnosticAndSelectionSteps() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "诊断安装" })
        XCTAssertTrue(DebugInstallGuidance.steps.contains { $0.title == "请求切换" })
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/diagnose-inputmethod.sh --strict"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/install-inputmethod.sh --with-prefpane"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/diagnose-inputmethod.sh --strict --logs"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/repair-inputmethod-selection.sh"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh"))
        XCTAssertTrue(DebugInstallGuidance.commands.contains("./scripts/select-inputmethod.sh --require-selected"))
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "请求切换"
                && $0.detail.contains("激活要测试的文本 app")
                && $0.detail.contains("实际输入探针")
        })
    }

    func testGuidanceExplainsSelectionRepair() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "刷新注册状态"
                && $0.detail.contains("LaunchServices")
                && $0.detail.contains("legacy .Mode")
                && $0.detail.contains(".Hans")
                && $0.detail.contains("third-party parent anchor")
        })
    }

    func testGuidanceExplainsInputMethodAuthorizationPrompt() {
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "启用输入源"
                && $0.detail.contains("允许")
                && $0.detail.contains("知键")
                && $0.detail.contains("KnowType")
        })
    }

    func testGuidanceKeepsAppleDevelopmentInstallCommand() {
        XCTAssertTrue(DebugInstallGuidance.commands.contains {
            $0.contains("CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\"")
        })
        XCTAssertTrue(DebugInstallGuidance.steps.contains {
            $0.title == "安装 bundle"
                && $0.detail.contains("输入法菜单")
        })
    }
}
