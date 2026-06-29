import CoreGraphics
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputClientCompositionWriterTests: XCTestCase {
    func testInlineCompositionWritesAttributedPreedit() {
        let writer = InputClientCompositionWriter(compatibilityPolicy: InputClientCompatibilityPolicy(userDefaults: nil))
        let client = WriteClient()
        let state = InputClientCompositionWriteState(
            compositionID: 7,
            rawLength: 2,
            inputModeState: .init(),
            hasActiveComposition: true
        )

        XCTAssertTrue(
            writer.refreshComposition(
                client: client,
                state: state,
                markedDisplayText: "ni"
            )
        )

        XCTAssertEqual(client.markedTextWrites.count, 1)
        XCTAssertEqual(client.markedTextWrites[0].text, "ni")
        XCTAssertTrue(client.markedTextWrites[0].isAttributed)
        XCTAssertEqual(client.markedTextWrites[0].selectionRange, NSRange(location: 2, length: 0))
        XCTAssertEqual(
            client.markedTextWrites[0].replacementRange,
            InputClientWriteCoordinator.noOwnedReplacementRange
        )
        XCTAssertNil(
            writer.candidatePanelPreeditDisplayText(
                client: client,
                state: state,
                markedDisplayText: "ni"
            )
        )
    }

    func testCommitOnlyCompositionWritesPlaceholderAndKeepsPreeditForPanel() {
        let suiteName = "KnowTypeInputClientCompositionWriterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            InputClientWriteMode.commitOnlyComposition.rawValue,
            forKey: "input.client.com.example.Terminal.writeMode"
        )
        let writer = InputClientCompositionWriter(compatibilityPolicy: InputClientCompatibilityPolicy(userDefaults: defaults))
        let client = WriteClient(bundleIdentifier: "com.example.Terminal")
        let state = InputClientCompositionWriteState(
            compositionID: 8,
            rawLength: 2,
            inputModeState: .init(),
            hasActiveComposition: true
        )

        XCTAssertTrue(
            writer.refreshComposition(
                client: client,
                state: state,
                markedDisplayText: "ni"
            )
        )

        XCTAssertEqual(client.markedTextWrites.count, 1)
        XCTAssertEqual(client.markedTextWrites[0].text, "\u{3000}")
        XCTAssertTrue(client.markedTextWrites[0].isAttributed)
        XCTAssertEqual(client.markedTextWrites[0].selectionRange, NSRange(location: 0, length: 0))
        XCTAssertEqual(
            writer.candidatePanelPreeditDisplayText(
                client: client,
                state: state,
                markedDisplayText: "ni"
            ),
            "ni"
        )
    }

    func testInsertClearsOwnedMarkedTextBeforeInsert() {
        let writer = InputClientCompositionWriter(compatibilityPolicy: InputClientCompatibilityPolicy(userDefaults: nil))
        let client = WriteClient()
        let activeState = InputClientCompositionWriteState(
            compositionID: 9,
            rawLength: 2,
            inputModeState: .init(),
            hasActiveComposition: true
        )

        XCTAssertTrue(
            writer.refreshComposition(
                client: client,
                state: activeState,
                markedDisplayText: "ni"
            )
        )
        writer.insertText(
            "你",
            client: client,
            state: activeState,
            reason: "commit"
        )

        XCTAssertEqual(client.writeEventKinds, ["markedText", "markedText", "insertText"])
        XCTAssertEqual(client.markedTextWrites[1].text, "")
        XCTAssertEqual(client.insertTextWrites.last?.text, "你")
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            InputClientWriteCoordinator.noOwnedReplacementRange
        )
    }

    func testIdleAsciiPassthroughUsesAsciiModeWithoutWriting() {
        let writer = InputClientCompositionWriter(compatibilityPolicy: InputClientCompatibilityPolicy(userDefaults: nil))
        let client = WriteClient()
        let state = InputClientCompositionWriteState(
            compositionID: 10,
            rawLength: 0,
            inputModeState: InputModeState(textMode: .ascii),
            hasActiveComposition: false
        )

        XCTAssertTrue(
            writer.shouldPassThroughIdleText(
                "a",
                client: client,
                state: state,
                reason: "idle_append"
            )
        )
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
    }
}

private final class WriteClient: InputControllerClient, @unchecked Sendable {
    struct MarkedTextWrite: Equatable {
        var text: String
        var isAttributed: Bool
        var selectionRange: NSRange
        var replacementRange: NSRange
    }

    struct InsertTextWrite: Equatable {
        var text: String
        var replacementRange: NSRange
    }

    let bundleIdentifier: String?
    var selectedRange = NSRange(location: 10, length: 0)
    var markedRange: NSRange?
    private(set) var markedTextWrites: [MarkedTextWrite] = []
    private(set) var insertTextWrites: [InsertTextWrite] = []
    private(set) var writeEventKinds: [String] = []

    init(bundleIdentifier: String? = "com.example.Host") {
        self.bundleIdentifier = bundleIdentifier
    }

    func firstRect(forCharacterRange _: NSRange) -> CGRect {
        CGRect(x: 10, y: 20, width: 0, height: 18)
    }

    func lineHeightRect(forCharacterIndex _: Int) -> CGRect {
        CGRect(x: 10, y: 20, width: 0, height: 18)
    }

    func setMarkedText(
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        writeEventKinds.append("markedText")
        markedTextWrites.append(
            MarkedTextWrite(
                text: text.string,
                isAttributed: text.isAttributed,
                selectionRange: selectionRange,
                replacementRange: replacementRange
            )
        )
        markedRange = text.string.isEmpty
            ? nil
            : NSRange(location: selectedRange.location, length: (text.string as NSString).length)
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        writeEventKinds.append("insertText")
        insertTextWrites.append(InsertTextWrite(text: text, replacementRange: replacementRange))
    }
}
