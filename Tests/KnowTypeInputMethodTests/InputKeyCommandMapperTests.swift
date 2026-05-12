import XCTest
@testable import KnowTypeInputMethod

final class InputKeyCommandMapperTests: XCTestCase {
    private let mapper = InputKeyCommandMapper()

    func testMapsSpaceTabAndDelete() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: " ", keyCode: 49)), .action(.space))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "\t", keyCode: 48)), .action(.tab))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "", keyCode: 51)), .deleteBackward)
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

    func testPlainTextAppendsToComposition() {
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "w", keyCode: 13)), .append("w"))
        XCTAssertEqual(mapper.intent(for: InputKeyStroke(text: "", keyCode: 123)), .ignored)
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
