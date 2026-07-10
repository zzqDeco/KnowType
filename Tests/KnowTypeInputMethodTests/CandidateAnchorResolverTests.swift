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

    func testResolverBoundsMaliciousHostGeometryProbes() {
        let accessibility = FakeAccessibilityAnchorProvider(rect: .infinite)
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 1_000, length: 1),
            markedRange: NSRange(location: 10, length: 200),
            defaultFirstRect: .infinite,
            defaultLineRect: CGRect(x: CGFloat.nan, y: 0, width: 0, height: 18)
        )
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: accessibility
        )

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .safeScreenFallback)
        XCTAssertEqual(client.requestedFirstRects.count, CandidateAnchorPolicy.maximumFirstRectProbes)
        XCTAssertLessThanOrEqual(
            client.requestedLineRects.count,
            CandidateAnchorPolicy.maximumLineHeightProbes
        )
        XCTAssertEqual(accessibility.callCount, 1)
    }

    func testResolverUsesOnlyStrategicLineHeightIndexes() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 105, length: 0),
            markedRange: NSRange(location: 100, length: 5),
            firstRects: [
                NSRange(location: 105, length: 0): .zero,
                NSRange(location: 100, length: 0): .zero
            ],
            lineRects: [
                0: CGRect(x: 33, y: 44, width: 0, height: 18)
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screenProvider())

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .lineHeightRect)
        XCTAssertEqual(result.rect, CGRect(x: 33, y: 44, width: 0, height: 18))
        XCTAssertEqual(client.requestedLineRects, [4, 0])
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

    func testResolverUsesScopedCacheBeforeLineHeightAndAccessibility() {
        let accessibility = FakeAccessibilityAnchorProvider(
            rect: CGRect(x: 300, y: 300, width: 0, height: 20)
        )
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: accessibility
        )
        let anchor = CGRect(x: 60, y: 60, width: 0, height: 18)
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [NSRange(location: 0, length: 0): anchor]
            ),
            context: context(now: 1_000)
        )
        let failedClient = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [NSRange(location: 0, length: 0): .zero],
            lineRects: [0: CGRect(x: 200, y: 200, width: 0, height: 18)]
        )

        let result = resolver.resolve(
            client: failedClient,
            context: context(now: 1_000.05)
        )

        XCTAssertEqual(result.source, .lastUsableScoped)
        XCTAssertEqual(result.rect, anchor)
        XCTAssertEqual(failedClient.requestedLineRects, [])
        XCTAssertEqual(accessibility.callCount, 0)
    }

    func testMultiScreenCacheDoesNotSuppressLineHeightAnchorOnCurrentDisplay() {
        let screens = multiScreenProvider()
        let accessibility = FakeAccessibilityAnchorProvider(rect: nil)
        let resolver = CandidateAnchorResolver(
            screenProvider: screens,
            accessibilityProvider: accessibility
        )
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [
                    NSRange(location: 0, length: 0): CGRect(x: 60, y: 60, width: 0, height: 18)
                ]
            ),
            context: context(now: 1_000)
        )
        let currentAnchor = CGRect(x: 900, y: 80, width: 0, height: 18)
        let movedClient = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [NSRange(location: 0, length: 0): .zero],
            lineRects: [0: currentAnchor]
        )

        let result = resolver.resolve(
            client: movedClient,
            context: context(now: 1_000.05)
        )

        XCTAssertEqual(result.source, .lineHeightRect)
        XCTAssertEqual(result.rect, currentAnchor)
        XCTAssertEqual(movedClient.requestedLineRects, [0])
        XCTAssertEqual(accessibility.callCount, 0)
    }

    func testMultiScreenCacheDoesNotSuppressAccessibilityAnchorOnCurrentDisplay() {
        let screens = multiScreenProvider()
        let currentAnchor = CGRect(x: 940, y: 100, width: 0, height: 20)
        let accessibility = FakeAccessibilityAnchorProvider(rect: currentAnchor)
        let resolver = CandidateAnchorResolver(
            screenProvider: screens,
            accessibilityProvider: accessibility
        )
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [
                    NSRange(location: 0, length: 0): CGRect(x: 60, y: 60, width: 0, height: 18)
                ]
            ),
            context: context(now: 1_000)
        )

        let result = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [NSRange(location: 0, length: 0): .zero],
                lineRects: [0: .zero]
            ),
            context: context(now: 1_000.05)
        )

        XCTAssertEqual(result.source, .accessibilityFocusedRange)
        XCTAssertEqual(result.rect, currentAnchor)
        XCTAssertEqual(accessibility.callCount, 1)
    }

    func testAccessibilityProbeIsThrottledByCompositionAndAppFor100Milliseconds() {
        var monotonicTime: TimeInterval = 1_000
        let accessibility = FakeAccessibilityAnchorProvider(rect: nil)
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: accessibility,
            monotonicNow: { monotonicTime }
        )
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil
        )

        XCTAssertEqual(
            resolver.resolve(client: client, context: context(now: 1_000)).source,
            .safeScreenFallback
        )
        XCTAssertEqual(accessibility.callCount, 1)

        monotonicTime += 0.05
        _ = resolver.resolve(client: client, context: context(now: 1_000.05))
        XCTAssertEqual(accessibility.callCount, 1)

        _ = resolver.resolve(
            client: client,
            context: context(appBundleID: "com.example.other", now: 1_000.05)
        )
        XCTAssertEqual(accessibility.callCount, 2)

        _ = resolver.resolve(
            client: client,
            context: context(compositionID: 2, now: 1_000.05)
        )
        XCTAssertEqual(accessibility.callCount, 3)

        monotonicTime = 1_000 + CandidateAnchorResolver.accessibilityThrottleInterval + 0.001
        _ = resolver.resolve(client: client, context: context(now: 1_000.1))
        XCTAssertEqual(accessibility.callCount, 4)
    }

    func testAccessibilityThrottleStartsAtAttemptAfterSlowHostProbes() {
        var monotonicTime: TimeInterval = 1_000
        let accessibility = FakeAccessibilityAnchorProvider(rect: nil)
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: accessibility,
            monotonicNow: { monotonicTime }
        )
        let slowClient = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            onLineHeightRect: { monotonicTime += 0.2 }
        )

        _ = resolver.resolve(client: slowClient, context: context(now: 1_000))
        XCTAssertEqual(accessibility.callCount, 1)

        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil
            ),
            context: context(now: 1_000.2)
        )
        XCTAssertEqual(accessibility.callCount, 1)

        monotonicTime += CandidateAnchorResolver.accessibilityThrottleInterval + 0.001
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil
            ),
            context: context(now: 1_000.3)
        )
        XCTAssertEqual(accessibility.callCount, 2)
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
            .safeScreenFallback
        )
        XCTAssertEqual(
            resolver.resolve(
                client: failedClient,
                context: context(compositionID: 7, appBundleID: "com.example.two")
            ).source,
            .safeScreenFallback
        )
    }

    func testLastUsableExpiresBeforeLineHeightAndAccessibilityFallbacks() {
        let accessibility = FakeAccessibilityAnchorProvider(rect: nil)
        let resolver = CandidateAnchorResolver(
            screenProvider: screenProvider(),
            accessibilityProvider: accessibility,
            maxLastUsableAge: 2
        )
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [
                    NSRange(location: 0, length: 0): CGRect(x: 60, y: 60, width: 0, height: 18)
                ]
            ),
            context: context(now: 1_000)
        )

        let result = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil
            ),
            context: context(now: 1_002.01)
        )

        XCTAssertEqual(result.source, .safeScreenFallback)
        XCTAssertEqual(accessibility.callCount, 1)
    }

    func testLastUsableRejectsChangedScreenIdentityInMultiScreenTopology() {
        let screens = FakeScreenGeometryProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
                ),
                CandidateAnchorScreen(
                    identifier: "secondary",
                    frame: CGRect(x: 800, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 800, y: 0, width: 800, height: 760)
                )
            ]
        )
        let resolver = CandidateAnchorResolver(screenProvider: screens)
        _ = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil,
                firstRects: [
                    NSRange(location: 0, length: 0): CGRect(x: 900, y: 60, width: 0, height: 18)
                ]
            ),
            context: context(now: 1_000)
        )
        screens.screens[1].identifier = "replacement"

        let result = resolver.resolve(
            client: FakeInputClientGeometry(
                selectedRange: NSRange(location: 0, length: 0),
                markedRange: nil
            ),
            context: context(now: 1_000.05)
        )

        XCTAssertEqual(result.source, .safeScreenFallback)
        XCTAssertLessThan(result.rect.minX, 800)
    }

    func testResolverUsesSafeScreenFallbackAfterAllAnchorSourcesFail() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero
            ],
            lineRects: [0: .zero]
        )
        let provider = screenProvider()
        let resolver = CandidateAnchorResolver(screenProvider: provider)

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .safeScreenFallback)
        XCTAssertFalse(result.isFresh)
        XCTAssertTrue(CandidateAnchorValidation.isUsable(result.rect, screenProvider: provider))
    }

    func testResolverReturnsNoneWhenNoScreenCanHostFallback() {
        let client = FakeInputClientGeometry(
            selectedRange: NSRange(location: 0, length: 0),
            markedRange: nil,
            firstRects: [
                NSRange(location: 0, length: 0): .zero
            ],
            lineRects: [0: .zero]
        )
        let resolver = CandidateAnchorResolver(
            screenProvider: FakeScreenGeometryProvider(screens: [])
        )

        let result = resolver.resolve(client: client, context: context())

        XCTAssertEqual(result.source, .none)
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
        appBundleID: String? = "com.example.app",
        now: TimeInterval = 1_000
    ) -> CandidateAnchorContext {
        CandidateAnchorContext(
            compositionID: compositionID,
            appBundleID: appBundleID,
            now: Date(timeIntervalSince1970: now)
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

    private func multiScreenProvider() -> FakeScreenGeometryProvider {
        FakeScreenGeometryProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
                ),
                CandidateAnchorScreen(
                    identifier: "secondary",
                    frame: CGRect(x: 800, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 800, y: 0, width: 800, height: 760)
                )
            ]
        )
    }
}

private final class FakeScreenGeometryProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]

    init(screens: [CandidateAnchorScreen]) {
        self.screens = screens
    }
}

private final class FakeAccessibilityAnchorProvider: AccessibilityAnchorProviding {
    var rect: CGRect?
    private(set) var callCount = 0

    init(rect: CGRect?) {
        self.rect = rect
    }

    func focusedCaretRect(screenProvider: ScreenGeometryProviding) -> CGRect? {
        callCount += 1
        return rect
    }
}

private final class FakeInputClientGeometry: InputClientGeometryProviding {
    var selectedRange: NSRange
    var markedRange: NSRange?
    var firstRects: [NSRange: CGRect]
    var lineRects: [Int: CGRect]
    var defaultFirstRect: CGRect
    var defaultLineRect: CGRect
    var requestedFirstRects: [NSRange] = []
    var requestedLineRects: [Int] = []
    var onLineHeightRect: (() -> Void)?

    init(
        selectedRange: NSRange,
        markedRange: NSRange?,
        firstRects: [NSRange: CGRect] = [:],
        lineRects: [Int: CGRect] = [:],
        defaultFirstRect: CGRect = .zero,
        defaultLineRect: CGRect = .zero,
        onLineHeightRect: (() -> Void)? = nil
    ) {
        self.selectedRange = selectedRange
        self.markedRange = markedRange
        self.firstRects = firstRects
        self.lineRects = lineRects
        self.defaultFirstRect = defaultFirstRect
        self.defaultLineRect = defaultLineRect
        self.onLineHeightRect = onLineHeightRect
    }

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        requestedFirstRects.append(range)
        return firstRects[range] ?? defaultFirstRect
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        requestedLineRects.append(index)
        onLineHeightRect?()
        return lineRects[index] ?? defaultLineRect
    }
}
