import CoreGraphics
import Foundation

public enum CandidateAnchorSource: String, Sendable, Equatable {
    case firstRectMarkedEnd
    case firstRectSelectedEnd
    case firstRectMarkedStart
    case firstRectSelectedStart
    case firstRectInsertionPoint
    case lineHeightRect
    case accessibilityFocusedRange
    case lastUsableScoped
    case none
}

public struct CandidateAnchorContext: Sendable, Equatable {
    public var compositionID: Int
    public var appBundleID: String?
    public var now: Date

    public init(
        compositionID: Int,
        appBundleID: String? = nil,
        now: Date = Date()
    ) {
        self.compositionID = compositionID
        self.appBundleID = appBundleID
        self.now = now
    }
}

public struct CandidateAnchorResult: Sendable, Equatable {
    public var rect: CGRect
    public var source: CandidateAnchorSource
    public var isFresh: Bool

    public init(rect: CGRect, source: CandidateAnchorSource, isFresh: Bool) {
        self.rect = rect
        self.source = source
        self.isFresh = isFresh
    }

    public static let none = CandidateAnchorResult(rect: .zero, source: .none, isFresh: false)
}

public struct CandidateAnchorCharacterRange: Sendable, Equatable {
    public var range: NSRange
    public var source: CandidateAnchorSource

    public init(range: NSRange, source: CandidateAnchorSource) {
        self.range = range
        self.source = source
    }
}

public struct CandidateAnchorScreen: Sendable, Equatable {
    public var identifier: String
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(identifier: String, frame: CGRect, visibleFrame: CGRect) {
        self.identifier = identifier
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public protocol ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen] { get }
}

public extension ScreenGeometryProviding {
    func screen(containing rect: CGRect) -> CandidateAnchorScreen? {
        let point = CGPoint(x: rect.minX, y: rect.midY)
        return screens.first { screen in
            screen.frame.insetBy(dx: -2, dy: -2).contains(point)
        } ?? screens.first { screen in
            let expandedRect = rect.insetBy(dx: rect.width == 0 ? -1 : 0, dy: -1)
            return screen.frame.intersects(expandedRect)
        }
    }
}

public protocol InputClientGeometryProviding {
    var selectedRange: NSRange { get }
    var markedRange: NSRange? { get }
    func firstRect(forCharacterRange range: NSRange) -> CGRect
    func lineHeightRect(forCharacterIndex index: Int) -> CGRect
}

public protocol AccessibilityAnchorProviding {
    func focusedCaretRect(screenProvider: ScreenGeometryProviding) -> CGRect?
}

public struct NoopAccessibilityAnchorProvider: AccessibilityAnchorProviding {
    public init() {}

    public func focusedCaretRect(screenProvider: ScreenGeometryProviding) -> CGRect? {
        nil
    }
}

public enum CandidateAnchorRejectionReason: String, Sendable, Equatable {
    case nullRect
    case infiniteRect
    case nonFiniteCoordinate
    case negativeSize
    case zeroHeight
    case offscreen
}

public enum CandidateAnchorValidation {
    public static let minimumCaretHeight: CGFloat = 3

    public static func rejectionReason(
        for rect: CGRect,
        screenProvider: ScreenGeometryProviding
    ) -> CandidateAnchorRejectionReason? {
        if rect.isNull {
            return .nullRect
        }
        if rect.isInfinite {
            return .infiniteRect
        }
        guard rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return .nonFiniteCoordinate
        }
        if rect.width < 0 || rect.height < 0 {
            return .negativeSize
        }
        if rect.height <= minimumCaretHeight {
            return .zeroHeight
        }
        if screenProvider.screen(containing: rect) == nil {
            return .offscreen
        }
        return nil
    }

    public static func isUsable(
        _ rect: CGRect,
        screenProvider: ScreenGeometryProviding
    ) -> Bool {
        rejectionReason(for: rect, screenProvider: screenProvider) == nil
    }
}

public enum CandidateAnchorCoordinateConverter {
    public static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        screens: [CandidateAnchorScreen]
    ) -> CGRect? {
        guard !rect.isNull,
              !rect.isInfinite,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }

        for screen in screens {
            let converted = CGRect(
                x: rect.minX,
                y: screen.frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            let point = CGPoint(x: converted.minX, y: converted.midY)
            if screen.frame.insetBy(dx: -2, dy: -2).contains(point) {
                return converted
            }
        }
        return nil
    }
}

public final class CandidateAnchorResolver {
    private struct ScopedAnchor {
        var rect: CGRect
        var compositionID: Int
        var appBundleID: String?
        var screenID: String
        var source: CandidateAnchorSource
        var timestamp: Date
    }

    private let screenProvider: ScreenGeometryProviding
    private let accessibilityProvider: AccessibilityAnchorProviding
    private let maxLastUsableAge: TimeInterval
    private let traceEnabled: Bool
    private var lastUsable: ScopedAnchor?

    public init(
        screenProvider: ScreenGeometryProviding,
        accessibilityProvider: AccessibilityAnchorProviding = NoopAccessibilityAnchorProvider(),
        maxLastUsableAge: TimeInterval = 2,
        traceEnabled: Bool = ProcessInfo.processInfo.environment["KNOWTYPE_ANCHOR_DEBUG"] == "1"
    ) {
        self.screenProvider = screenProvider
        self.accessibilityProvider = accessibilityProvider
        self.maxLastUsableAge = maxLastUsableAge
        self.traceEnabled = traceEnabled
    }

    public func reset() {
        lastUsable = nil
    }

    public func resolve(
        client: InputClientGeometryProviding?,
        context: CandidateAnchorContext
    ) -> CandidateAnchorResult {
        if let client {
            for request in CandidateAnchorPolicy.characterRangeRequests(
                selectedRange: client.selectedRange,
                markedRange: client.markedRange
            ) {
                if let result = freshResult(
                    rect: client.firstRect(forCharacterRange: request.range),
                    source: request.source,
                    context: context
                ) {
                    return result
                }
            }

            if let result = freshResult(
                rect: client.firstRect(forCharacterRange: CandidateAnchorPolicy.currentInsertionPointFallbackRange),
                source: .firstRectInsertionPoint,
                context: context
            ) {
                return result
            }

            for index in CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: client.selectedRange,
                markedRange: client.markedRange
            ) {
                if let result = freshResult(
                    rect: client.lineHeightRect(forCharacterIndex: index),
                    source: .lineHeightRect,
                    context: context
                ) {
                    return result
                }
            }
        }

        if let accessibilityRect = accessibilityProvider.focusedCaretRect(screenProvider: screenProvider),
           let result = freshResult(
               rect: accessibilityRect,
               source: .accessibilityFocusedRange,
               context: context
           ) {
            return result
        }

        if let result = scopedLastUsableResult(context: context) {
            return result
        }

        trace(source: .none, rect: .zero, accepted: false, reason: "no-anchor", context: context)
        return .none
    }

    private func freshResult(
        rect: CGRect,
        source: CandidateAnchorSource,
        context: CandidateAnchorContext
    ) -> CandidateAnchorResult? {
        guard CandidateAnchorValidation.isUsable(rect, screenProvider: screenProvider),
              let screen = screenProvider.screen(containing: rect) else {
            let reason = CandidateAnchorValidation
                .rejectionReason(for: rect, screenProvider: screenProvider)?
                .rawValue ?? "unknown"
            trace(source: source, rect: rect, accepted: false, reason: reason, context: context)
            return nil
        }
        lastUsable = ScopedAnchor(
            rect: rect,
            compositionID: context.compositionID,
            appBundleID: context.appBundleID,
            screenID: screen.identifier,
            source: source,
            timestamp: context.now
        )
        trace(source: source, rect: rect, accepted: true, reason: nil, context: context)
        return CandidateAnchorResult(rect: rect, source: source, isFresh: true)
    }

    private func scopedLastUsableResult(context: CandidateAnchorContext) -> CandidateAnchorResult? {
        guard let lastUsable,
              lastUsable.compositionID == context.compositionID,
              lastUsable.appBundleID == context.appBundleID,
              context.now.timeIntervalSince(lastUsable.timestamp) <= maxLastUsableAge,
              let screen = screenProvider.screen(containing: lastUsable.rect),
              screen.identifier == lastUsable.screenID,
              CandidateAnchorValidation.isUsable(lastUsable.rect, screenProvider: screenProvider) else {
            return nil
        }
        trace(source: .lastUsableScoped, rect: lastUsable.rect, accepted: true, reason: nil, context: context)
        return CandidateAnchorResult(rect: lastUsable.rect, source: .lastUsableScoped, isFresh: false)
    }

    private func trace(
        source: CandidateAnchorSource,
        rect: CGRect,
        accepted: Bool,
        reason: String?,
        context: CandidateAnchorContext
    ) {
        guard traceEnabled else {
            return
        }
        let status = accepted ? "accepted" : "rejected"
        let reasonText = reason.map { " reason=\($0)" } ?? ""
        let message = "KnowTypeAnchor source=\(source.rawValue) status=\(status) rect=\(rect) bundle=\(context.appBundleID ?? "-") composition=\(context.compositionID)\(reasonText)"
        fputs("\(message)\n", stderr)
        NSLog("%@", message)
    }
}

public enum CandidateAnchorRefreshPolicy {
    public static func shouldApplyDelayedAnchor(
        snapshotRawInput: String,
        currentRawInput: String,
        snapshotCompositionID: Int,
        currentCompositionID: Int,
        isPanelVisible: Bool
    ) -> Bool {
        isPanelVisible
            && !snapshotRawInput.isEmpty
            && snapshotRawInput == currentRawInput
            && snapshotCompositionID == currentCompositionID
    }
}

#if canImport(AppKit)
import AppKit

public struct AppKitScreenGeometryProvider: ScreenGeometryProviding {
    public init() {}

    public var screens: [CandidateAnchorScreen] {
        NSScreen.screens.enumerated().map { index, screen in
            let identifier = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .stringValue ?? "\(index)"
            return CandidateAnchorScreen(
                identifier: identifier,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }
}

#if canImport(ApplicationServices)
import ApplicationServices

public struct SystemAccessibilityAnchorProvider: AccessibilityAnchorProviding {
    public init() {}

    public func focusedCaretRect(screenProvider: ScreenGeometryProviding) -> CGRect? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedElement = focusedValue else {
            return nil
        }
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedAXElement = focusedElement as! AXUIElement

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedAXElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
              let selectedRangeValue,
              CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedAXElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsValue
        ) == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var accessibilityRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &accessibilityRect) else {
            return nil
        }
        return CandidateAnchorCoordinateConverter.appKitRect(
            fromAccessibilityRect: accessibilityRect,
            screens: screenProvider.screens
        )
    }
}
#endif
#endif

#if canImport(InputMethodKit)
@preconcurrency import InputMethodKit

struct IMKTextInputGeometryAdapter: InputClientGeometryProviding {
    private let client: IMKTextInput

    init(client: IMKTextInput) {
        self.client = client
    }

    var selectedRange: NSRange {
        client.selectedRange()
    }

    var markedRange: NSRange? {
        let range = client.markedRange()
        guard range.location != NSNotFound,
              range.length != NSNotFound else {
            return nil
        }
        return range
    }

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        client.firstRect(forCharacterRange: range, actualRange: nil)
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        return rect
    }
}
#endif
