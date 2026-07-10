import KnowTypeInputSourceSupport
import XCTest

final class InputMethodHostStartupPolicyTests: XCTestCase {
    func testServeOnlyStartupDoesNotWaitWhenParentAndModeNeverBecomeVisible() {
        var didServeInputMethod = false
        var waitedSourceIDs: [String] = []
        let waitForInputSource: (String) -> Bool = { sourceID in
            waitedSourceIDs.append(sourceID)
            return false
        }

        let exitCode = KnowTypeInputMethodStartupPolicy.run(
            explicitCommandRequested: false,
            serveInputMethod: {
                didServeInputMethod = true
            },
            runExplicitCommand: {
                let parentVisible = waitForInputSource(KnowTypeInputSourceIDs.parent)
                let modeVisible = waitForInputSource(KnowTypeInputSourceIDs.activeMode)
                return parentVisible && modeVisible ? 0 : 1
            }
        )

        XCTAssertTrue(didServeInputMethod)
        XCTAssertTrue(waitedSourceIDs.isEmpty)
        XCTAssertNil(exitCode)
    }

    func testExplicitCommandRunsWaitPathWithoutStartingServer() {
        var didServeInputMethod = false
        var waitedSourceIDs: [String] = []
        let waitForInputSource: (String) -> Bool = { sourceID in
            waitedSourceIDs.append(sourceID)
            return false
        }

        let exitCode = KnowTypeInputMethodStartupPolicy.run(
            explicitCommandRequested: true,
            serveInputMethod: {
                didServeInputMethod = true
            },
            runExplicitCommand: {
                let parentVisible = waitForInputSource(KnowTypeInputSourceIDs.parent)
                let modeVisible = waitForInputSource(KnowTypeInputSourceIDs.activeMode)
                return parentVisible && modeVisible ? 0 : 1
            }
        )

        XCTAssertFalse(didServeInputMethod)
        XCTAssertEqual(
            waitedSourceIDs,
            [KnowTypeInputSourceIDs.parent, KnowTypeInputSourceIDs.activeMode]
        )
        XCTAssertEqual(exitCode, 1)
    }
}
