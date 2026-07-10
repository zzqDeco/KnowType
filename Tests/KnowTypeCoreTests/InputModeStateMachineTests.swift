import XCTest
@testable import KnowTypeCore

final class InputModeStateMachineTests: XCTestCase {
    func testStartsInLinkedChineseModeWithConfiguredWidth() {
        let machine = InputModeStateMachine(symbolWidth: .fullWidth)

        XCTAssertEqual(
            machine.snapshot,
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

    func testTextModeToggleSynchronizesPunctuationAndClearsManualOverride() {
        var machine = InputModeStateMachine()

        _ = machine.transition(.togglePunctuationMode)
        XCTAssertEqual(machine.snapshot.state.punctuationMode, .english)
        XCTAssertEqual(machine.snapshot.punctuationSource, .manual)

        _ = machine.transition(.toggleTextMode)
        XCTAssertEqual(machine.snapshot.state.textMode, .ascii)
        XCTAssertEqual(machine.snapshot.state.punctuationMode, .english)
        XCTAssertEqual(machine.snapshot.punctuationSource, .linked)

        _ = machine.transition(.toggleTextMode)
        XCTAssertEqual(machine.snapshot.state.textMode, .chinese)
        XCTAssertEqual(machine.snapshot.state.punctuationMode, .chinese)
        XCTAssertEqual(machine.snapshot.punctuationSource, .linked)
    }

    func testPunctuationToggleIsNoopInASCIIMode() {
        var machine = InputModeStateMachine()
        _ = machine.transition(.toggleTextMode)
        let before = machine.snapshot

        let transition = machine.transition(.togglePunctuationMode)

        XCTAssertFalse(transition.didChange)
        XCTAssertEqual(machine.snapshot, before)
    }

    func testWidthRemainsIndependentAndGenerationOnlyTracksChanges() {
        var machine = InputModeStateMachine()

        _ = machine.transition(.toggleSymbolWidth)
        XCTAssertEqual(machine.snapshot.state.symbolWidth, .fullWidth)
        XCTAssertEqual(machine.snapshot.generation, 1)

        _ = machine.transition(.toggleTextMode)
        XCTAssertEqual(machine.snapshot.state.symbolWidth, .fullWidth)
        XCTAssertEqual(machine.snapshot.generation, 2)

        let unchanged = machine.transition(.setSymbolWidth(.fullWidth))
        XCTAssertFalse(unchanged.didChange)
        XCTAssertEqual(machine.snapshot.generation, 2)
    }
}
