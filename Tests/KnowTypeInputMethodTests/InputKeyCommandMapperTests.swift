import XCTest
@testable import KnowTypeInputMethod

final class InputKeyCommandMapperTests: XCTestCase {
    private let mapper = InputKeyCommandMapper()

    func testMapsSpaceTabAndDelete() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: " ", keyCode: 49)), .action(.space))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\t", keyCode: 48)), .action(.tab))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "", keyCode: 51)), .deleteBackward)
    }

    func testMapsTextOnlySpaceTabAndDelete() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: " ", keyCode: -1)), .action(.space))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\t", keyCode: -1)), .action(.tab))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\u{7F}", keyCode: -1)), .deleteBackward)
    }

    func testMapsOptionNumberToContinuationIndex() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "", keyCode: 18, modifiers: [.option])),
            .action(.optionNumber(1))
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "", keyCode: 19, modifiers: [.option])),
            .action(.optionNumber(2))
        )
    }

    func testMapsOptionRToPolish() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "", keyCode: 15, modifiers: [.option])),
            .action(.optionR)
        )
    }

    func testMapsOptionPeriodToSymbolModeToggle() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: ".", keyCode: 47, modifiers: [.option])),
            .action(.toggleSymbolMode)
        )
    }

    func testMapsOptionSlashToTextModeToggle() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option])),
            .action(.toggleTextMode)
        )
    }

    func testPlainTextAppendsToComposition() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "w", keyCode: 13)), .append("w"))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "中", keyCode: -1)), .append("中"))
    }

    func testPlainSymbolsUseSymbolIntent() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: ".", keyCode: 47)), .symbol("."))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "/", keyCode: 44)), .symbol("/"))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "!", keyCode: 18)), .symbol("!"))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "@", keyCode: 19)), .symbol("@"))
    }

    func testReturnAndEnterCommitRawComposition() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\r", keyCode: 36)), .action(.commitRaw))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\n", keyCode: 76)), .action(.commitRaw))
        XCTAssertFalse(InputKeyCommandMapper.isAppendableText("\r"))
    }

    func testMapsEscapeToCancelComposition() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\u{1B}", keyCode: 53)), .cancelComposition)
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "", keyCode: 53)), .cancelComposition)
    }

    func testAppKitFunctionKeyScalarsAreIgnored() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\u{F700}", keyCode: -1)), .ignored)
        XCTAssertFalse(InputKeyCommandMapper.isAppendableText("\u{F700}"))
        XCTAssertTrue(InputKeyCommandMapper.isAppendableText("中英 mixed text"))
    }

    func testMapsArrowAndPageKeysToCandidateNavigation() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F700}", keyCode: 126)),
            .moveCandidateSelection(.up)
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F701}", keyCode: 125)),
            .moveCandidateSelection(.down)
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F702}", keyCode: 123)),
            .moveCandidateSelection(.left)
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F703}", keyCode: 124)),
            .moveCandidateSelection(.right)
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F72C}", keyCode: 116)),
            .moveCandidateSelection(.pageUp)
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "\u{F72D}", keyCode: 121)),
            .moveCandidateSelection(.pageDown)
        )
    }

    func testMapsPlainNumberKeysToCandidateSelectionIntent() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "0", keyCode: 29)), .selectCandidate(0))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "1", keyCode: 18)), .selectCandidate(1))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "9", keyCode: 25)), .selectCandidate(9))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "1", keyCode: -1)), .append("1"))
    }

    func testKeyUpAndFlagsChangedAreModeledSeparately() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "w", keyCode: 13, eventKind: .keyUp)),
            .ignored
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "", keyCode: 58, modifiers: [.option], eventKind: .flagsChanged)),
            .modifierFlagsChanged([.option])
        )
    }

    func testCommandAndControlModifiedInputIsIgnored() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "c", keyCode: 8, modifiers: [.command])),
            .ignored
        )
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "v", keyCode: 9, modifiers: [.control])),
            .ignored
        )
    }

    func testUnrecognizedOptionInputIsIgnored() {
        XCTAssertEqual(
            mapper.intent(for: InputKeyStroke(text: "r", keyCode: 14, modifiers: [.option])),
            .ignored
        )
    }
}
