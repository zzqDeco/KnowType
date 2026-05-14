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

    func testValidationStandardizesNegativeSizeRects() {
        let rect = CGRect(x: 100, y: 100, width: -10, height: -18)

        XCTAssertTrue(
            CandidateAnchorValidation.isUsable(
                rect,
                screenProvider: screenProvider()
            )
        )
        XCTAssertEqual(
            CandidateAnchorValidation.normalized(rect),
            CGRect(x: 90, y: 82, width: 10, height: 18)
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
            selectedRange: NSRange(location: 105, length: 0),
            markedRange: NSRange(location: 100, length: 5),
            firstRects: [
                NSRange(location: 105, length: 0): .zero,
                NSRange(location: 100, length: 0): .zero
            ],
            lineRects: [
                3: CGRect(x: 33, y: 44, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .lineHeightRect)
        XCTAssertEqual(result.rect, CGRect(x: 33, y: 44, width: 0, height: 18))
        XCTAssertFalse(client.requestedLineRects.contains(5))
        XCTAssertEqual(client.requestedLineRects.prefix(2), [4, 3])
    }

    func testResolverUsesZeroLineHeightIndexWhenNoMarkedRangeExists() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 120, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 120, length: 0): .zero
            ],
            lineRects: [
                0: CGRect(x: 70, y: 80, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .lineHeightRect)
        XCTAssertEqual(result.rect, CGRect(x: 70, y: 80, width: 0, height: 18))
    }

    func testResolverDoesNotCallFirstRectWithUnknownInsertionPoint() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: NSNotFound, length: NSNotFound),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero
            ],
            lineRects: [
                0: CGRect(x: 40, y: 50, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertFalse(client.requestedFirstRects.contains(NSRange(location: NSNotFound, length: 0)))
        XCTAssertEqual(result.source, .lineHeightRect)
    }

    func testResolverReturnsStandardizedRectForNegativeSizeFirstRect() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 10, length: 0): CGRect(x: 100, y: 100, width: -10, height: -18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .firstRectSelectedEnd)
        XCTAssertEqual(result.rect, CGRect(x: 90, y: 82, width: 10, height: 18))
    }

    func testResolverUsesAccessibilityFallbackAfterIMKFailure() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero
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

    func testAccessibilityCoordinateConversionUsesMenuBarScreenTopForVerticalDisplays() {
        let screens = [
            CandidateAnchorScreen(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
            ),
            CandidateAnchorScreen(
                identifier: "upper",
                frame: CGRect(x: 0, y: 800, width: 800, height: 600),
                visibleFrame: CGRect(x: 0, y: 800, width: 800, height: 560)
            )
        ]

        XCTAssertEqual(
            CandidateAnchorCoordinateConverter.appKitRect(
                fromAccessibilityRect: CGRect(x: 100, y: -220, width: 0, height: 20),
                screens: screens
            ),
            CGRect(x: 100, y: 1_000, width: 0, height: 20)
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
                NSRange(location: 0, length: 0): .zero
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
                hasActiveComposition: true
            )
        )
        XCTAssertFalse(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "nish",
                snapshotCompositionID: 3,
                currentCompositionID: 3,
                hasActiveComposition: true
            )
        )
        XCTAssertFalse(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "ni",
                snapshotCompositionID: 3,
                currentCompositionID: 4,
                hasActiveComposition: true
            )
        )
        XCTAssertFalse(
            CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: "ni",
                currentRawInput: "ni",
                snapshotCompositionID: 3,
                currentCompositionID: 3,
                hasActiveComposition: false
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
    var requestedFirstRects: [NSRange] = []
    var requestedLineRects: [Int] = []

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
        requestedFirstRects.append(range)
        return firstRects[range] ?? .zero
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        requestedLineRects.append(index)
        return lineRects[index] ?? .zero
    }
}
