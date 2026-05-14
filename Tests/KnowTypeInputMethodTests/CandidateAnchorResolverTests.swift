import CoreGraphics
import Foundation
import XCTest
@testable import KnowTypeInputMethod

final class CandidateAnchorResolverTests: XCTestCase {
    func testValidationAcceptsZeroWidthCaretWithPositiveHeight() {
        XCTAssertTrue(
            CandidateAnchorValidation.isUsable(
                CGRect(x: 40, y: 40, width: 0, height: 18),
                screenProvider: screenProvider()
            )
        )
    }

    func testValidationRejectsZeroHeightAndOffscreenRects() {
        let screens = screenProvider()

        XCTAssertEqual(
            CandidateAnchorValidation.rejectionReason(
                for: CGRect(x: 40, y: 40, width: 0, height: 0),
                screenProvider: screens
            ),
            .zeroHeight
        )
        XCTAssertEqual(
            CandidateAnchorValidation.rejectionReason(
                for: CGRect(x: 2_000, y: 2_000, width: 0, height: 18),
                screenProvider: screens
            ),
            .offscreen
        )
    }

    func testResolverUsesIMKSourcePrecedence() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 30, length: 0),
            markedRange: NSRange(location: 10, length: 4),
            firstRects: [
                NSRange(location: 14, length: 0): CGRect(x: 10, y: 10, width: 0, height: 18),
                NSRange(location: 30, length: 0): CGRect(x: 30, y: 10, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .firstRectMarkedEnd)
        XCTAssertEqual(result.rect, CGRect(x: 10, y: 10, width: 0, height: 18))
        XCTAssertTrue(result.isFresh)
    }

    func testResolverFallsBackThroughLineHeightIndexesFromCursor() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 5, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 5, length: 0): .zero,
                CandidateAnchorPolicy.currentInsertionPointFallbackRange: .zero
            ],
            lineRects: [
                3: CGRect(x: 33, y: 44, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .lineHeightRect)
        XCTAssertEqual(result.rect, CGRect(x: 33, y: 44, width: 0, height: 18))
    }

    func testResolverUsesAccessibilityFallbackAfterIMKFailure() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero,
                CandidateAnchorPolicy.currentInsertionPointFallbackRange: .zero
            ],
            lineRects: [0: .zero]
        )
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: FakeAccessibilityAnchorProvider(
                rect: CGRect(x: 80, y: 90, width: 0, height: 20)
            )
        )

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .accessibilityFocusedRange)
        XCTAssertEqual(result.rect, CGRect(x: 80, y: 90, width: 0, height: 20))
    }

    func testAccessibilityCoordinateConversionUsesScreenTopOrigin() {
        XCTAssertEqual(
            CandidateAnchorCoordinateConverter.appKitRect(
                fromAccessibilityRect: CGRect(x: 100, y: 200, width: 0, height: 20),
                screens: screenProvider().screens
            ),
            CGRect(x: 100, y: 580, width: 0, height: 20)
        )
    }

    func testLastUsableIsScopedToCompositionBundleAndScreen() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): CGRect(x: 60, y: 60, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())
        _ = resolver.resolve(
            client: client,
            context: context(compositionID: 7, appBundleID: "com.example.one")
        )

        let failedClient = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero,
                CandidateAnchorPolicy.currentInsertionPointFallbackRange: .zero
            ],
            lineRects: [0: .zero]
        )

        XCTAssertEqual(
            resolver.resolve(
                client: failedClient,
                context: context(compositionID: 7, appBundleID: "com.example.one")
            ).source,
            .lastUsableScoped
        )
        XCTAssertEqual(
            resolver.resolve(
                client: failedClient,
                context: context(compositionID: 8, appBundleID: "com.example.one")
            ).source,
            .none
        )
        XCTAssertEqual(
            resolver.resolve(
                client: failedClient,
                context: context(compositionID: 7, appBundleID: "com.example.two")
            ).source,
            .none
        )
    }

    func testDelayedAnchorRefreshRequiresSameRawInputAndComposition() {
        XCTAssertTrue(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "ni",
                snapshotCompositionID: 3,
                currentCompositionID: 3,
                isPanelVisible: true
            )
        )
        XCTAssertFalse(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "nish",
                snapshotCompositionID: 3,
                currentCompositionID: 3,
                isPanelVisible: true
            )
        )
        XCTAssertFalse(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "ni",
                snapshotCompositionID: 3,
                currentCompositionID: 4,
                isPanelVisible: true
            )
        )
    }

    private func context(
        compositionID: Int = 1,
        appBundleID: String? = "com.example.app"
    ) -> CandidateAnchorContext {
        CandidateAnchorContext(
            compositionID: compositionID,
            appBundleID: appBundleID,
            now: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func screenProvider() -> FakeScreenGeometryProvider {
        FakeScreenGeometryProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
                )
            ]
        )
    }
}

private struct FakeScreenGeometryProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
}

private struct FakeAccessibilityAnchorProvider: AccessibilityAnchorProviding {
    var rect: CGRect?

    func focusedCaretRect(screenProvider: ScreenGeometryProviding) -> CGRect? {
        rect
    }
}

private final class FakeInputClientGeometry: InputClientGeometryProviding {
    var selectedRange: NSRange
    var markedRange: NSRange?
    var firstRects: [NSRange: CGRect]
    var lineRects: [Int: CGRect]

    init(
        selectedRange: NSRange,
        markedRange: NSRange?,
        firstRects: [NSRange: CGRect] = [:],
        lineRects: [Int: CGRect] = [:]
    ) {
        self.selectedRange = selectedRange
        self.markedRange = markedRange
        self.firstRects = firstRects
        self.lineRects = lineRects
    }

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        firstRects[range] ?? .zero
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        lineRects[index] ?? .zero
    }
}
