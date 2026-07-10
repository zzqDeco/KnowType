import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class ProcessInputModeStateRuntimeTests: XCTestCase {
    func testReferencesShareStateAndGeneration() {
        let runtime = ProcessInputModeStateRuntime()
        let first: any InputModeStateRuntime = runtime
        let second: any InputModeStateRuntime = runtime

        _ = first.transition(.toggleTextMode)

        XCTAssertEqual(second.currentSnapshot().state.textMode, .ascii)
        XCTAssertEqual(second.currentSnapshot().state.punctuationMode, .english)
        XCTAssertEqual(second.currentSnapshot().generation, 1)
    }

    func testNewRuntimeRestoresLinkedChineseMode() {
        let previousRuntime = ProcessInputModeStateRuntime()
        _ = previousRuntime.transition(.togglePunctuationMode)
        _ = previousRuntime.transition(.toggleTextMode)

        let restartedRuntime = ProcessInputModeStateRuntime(initialSymbolWidth: .fullWidth)

        XCTAssertEqual(
            restartedRuntime.currentSnapshot(),
            InputModeSnapshot(
                state: InputModeState(
                    textMode: .chinese,
                    punctuationMode: .chinese,
                    symbolWidth: .fullWidth
                ),
                punctuationSource: .linked,
                generation: 0
            )
        )
    }

    func testNewCoordinatorConfigurationDoesNotOverwriteManualWidth() {
        let runtime = ProcessInputModeStateRuntime(initialSymbolWidth: .halfWidth)
        _ = runtime.transition(.toggleSymbolWidth)

        let transition = runtime.synchronizeConfiguredSymbolWidth(.halfWidth)

        XCTAssertFalse(transition.didChange)
        XCTAssertEqual(runtime.currentSnapshot().state.symbolWidth, .fullWidth)
        XCTAssertEqual(runtime.currentSnapshot().generation, 1)
    }

    func testChangedConfigurationUpdatesCurrentWidthOnce() {
        let runtime = ProcessInputModeStateRuntime(initialSymbolWidth: .halfWidth)

        let changed = runtime.synchronizeConfiguredSymbolWidth(.fullWidth)
        let repeated = runtime.synchronizeConfiguredSymbolWidth(.fullWidth)

        XCTAssertTrue(changed.didChange)
        XCTAssertEqual(changed.current.state.symbolWidth, .fullWidth)
        XCTAssertEqual(changed.current.generation, 1)
        XCTAssertFalse(repeated.didChange)
        XCTAssertEqual(repeated.current.generation, 1)
    }
}
