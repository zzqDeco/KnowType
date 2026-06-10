import CryptoKit
import Foundation
import KnowTypeAI

final class AIAcceptedFeedbackTracker: @unchecked Sendable {
    private struct ActiveSpan {
        var acceptID: UUID
        var clientID: ObjectIdentifier
        var schemaID: String
        var appBundleID: String?
        var provider: String
        var contextVersion: String
        var acceptedTextHash: String
        var currentText: String
        var startLocation: Int
        var endLocation: Int
        var createdAt: Date
        var isVerified: Bool
        var pendingRanges: [AIAcceptedFeedbackTextRange]
        var pendingTexts: [String]
        var pendingVisibleCharacterCount: Int
        var replacementText: String?
        var debounceTask: Task<Void, Never>?
    }

    private let recorder: (any AIAcceptedFeedbackRecording)?
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let now: @Sendable () -> Date
    private let ttlSeconds: TimeInterval
    private let debounceNanoseconds: UInt64
    private let lock = NSLock()
    private var activeSpan: ActiveSpan?

    init(
        recorder: (any AIAcceptedFeedbackRecording)?,
        diagnosticSink: any AIRecommendationDiagnosticSink,
        ttlSeconds: TimeInterval = 90,
        debounceNanoseconds: UInt64 = 500_000_000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.diagnosticSink = diagnosticSink
        self.ttlSeconds = ttlSeconds
        self.debounceNanoseconds = debounceNanoseconds
        self.now = now
    }

    func armAcceptedSpan(
        acceptID: UUID,
        acceptedText: String,
        schemaID: String,
        appBundleID: String?,
        provider: String,
        contextVersion: String,
        client: InputControllerClient?
    ) -> Bool {
        guard recorder != nil,
              let client else {
            cancel(reason: "missing_recorder_or_client")
            return false
        }
        let selectedRange = client.selectedRange
        guard Self.isKnownCollapsedRange(selectedRange) else {
            cancel(reason: "pre_insert_range_unverified")
            return false
        }
        let acceptedLength = (acceptedText as NSString).length
        guard acceptedLength > 0 else {
            cancel(reason: "empty_accepted_text")
            return false
        }
        let startLocation = selectedRange.location
        let active = ActiveSpan(
            acceptID: acceptID,
            clientID: ObjectIdentifier(client),
            schemaID: schemaID,
            appBundleID: appBundleID,
            provider: provider,
            contextVersion: contextVersion,
            acceptedTextHash: Self.hash(acceptedText),
            currentText: acceptedText,
            startLocation: startLocation,
            endLocation: startLocation + acceptedLength,
            createdAt: now(),
            isVerified: false,
            pendingRanges: [],
            pendingTexts: [],
            pendingVisibleCharacterCount: 0,
            replacementText: nil,
            debounceTask: nil
        )
        lock.lock()
        activeSpan?.debounceTask?.cancel()
        activeSpan = active
        lock.unlock()
        return true
    }

    func verifyPostInsertCaret(client: InputControllerClient?) {
        guard let client else {
            cancel(reason: "post_insert_missing_client")
            return
        }
        lock.lock()
        guard var active = activeSpan else {
            lock.unlock()
            return
        }
        guard ObjectIdentifier(client) == active.clientID else {
            lock.unlock()
            cancel(reason: "post_insert_client_changed")
            return
        }
        let selectedRange = client.selectedRange
        guard Self.isKnownCollapsedRange(selectedRange),
              selectedRange.location == active.endLocation else {
            lock.unlock()
            cancel(reason: "post_insert_caret_unverified")
            return
        }
        active.isVerified = true
        activeSpan = active
        lock.unlock()
    }

    func observeDeleteBackward(client: InputControllerClient?) -> Bool {
        guard let client else {
            cancel(reason: "delete_missing_client")
            return false
        }
        let selectedRange = client.selectedRange
        lock.lock()
        guard var active = activeSpan else {
            lock.unlock()
            return false
        }
        guard active.isVerified else {
            lock.unlock()
            cancel(reason: "delete_before_verified")
            return false
        }
        guard now().timeIntervalSince(active.createdAt) <= ttlSeconds else {
            lock.unlock()
            cancel(reason: "expired")
            return false
        }
        guard ObjectIdentifier(client) == active.clientID else {
            lock.unlock()
            cancel(reason: "delete_client_changed")
            return false
        }
        guard let deleteRange = Self.deletedRange(
            for: selectedRange,
            activeStart: active.startLocation,
            activeEnd: active.endLocation,
            currentText: active.currentText
        ) else {
            lock.unlock()
            cancel(reason: "delete_range_unverified")
            return false
        }
        let relativeRange = NSRange(
            location: deleteRange.location - active.startLocation,
            length: deleteRange.length
        )
        let deletedText = (active.currentText as NSString).substring(with: relativeRange)
        active.currentText = (active.currentText as NSString)
            .replacingCharacters(in: relativeRange, with: "")
        active.endLocation -= deleteRange.length
        active.pendingRanges.append(
            AIAcceptedFeedbackTextRange(
                location: deleteRange.location,
                length: deleteRange.length
            )
        )
        active.pendingTexts.append(deletedText)
        active.pendingVisibleCharacterCount += deletedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count
        activeSpan = active
        lock.unlock()
        scheduleFlush()
        return true
    }

    func observeVerifiedReplacementCommit(_ text: String, client: InputControllerClient?) {
        guard let client,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        lock.lock()
        guard var active = activeSpan,
              active.isVerified,
              !active.pendingRanges.isEmpty,
              ObjectIdentifier(client) == active.clientID,
              Self.isKnownCollapsedRange(client.selectedRange),
              client.selectedRange.location >= active.startLocation,
              client.selectedRange.location <= active.endLocation else {
            lock.unlock()
            return
        }
        active.replacementText = text
        activeSpan = active
        lock.unlock()
        flushPending(reason: "replacement_commit")
    }

    func cancel(reason: String) {
        lock.lock()
        let hadActiveSpan = activeSpan != nil
        let pending = activeSpan?.pendingRanges.isEmpty == false
        lock.unlock()
        if pending {
            flushPending(reason: reason)
            return
        }
        guard hadActiveSpan else {
            return
        }
        lock.lock()
        activeSpan?.debounceTask?.cancel()
        activeSpan = nil
        lock.unlock()
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: .acceptedFeedbackTrackingCancelled,
                reason: reason
            )
        )
    }

    private func scheduleFlush() {
        lock.lock()
        activeSpan?.debounceTask?.cancel()
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: self.debounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self.flushPending(reason: "delete_idle")
        }
        activeSpan?.debounceTask = task
        lock.unlock()
    }

    private func flushPending(reason: String) {
        lock.lock()
        guard var active = activeSpan,
              !active.pendingRanges.isEmpty else {
            lock.unlock()
            return
        }
        active.debounceTask?.cancel()
        let acceptedLength = max(1, active.pendingRanges.reduce(0) { $0 + $1.length } + (active.currentText as NSString).length)
        let deletedLength = active.pendingRanges.reduce(0) { $0 + $1.length }
        let deletedRatio = min(1, Double(deletedLength) / Double(acceptedLength))
        let strength = Self.strength(
            deletedRatio: deletedRatio,
            visibleCharacterCount: active.pendingVisibleCharacterCount
        )
        let record = AIAcceptedFeedbackRecord(
            acceptID: active.acceptID,
            schemaID: active.schemaID,
            appBundleID: active.appBundleID,
            provider: active.provider,
            contextVersion: active.contextVersion,
            acceptedTextHash: active.acceptedTextHash,
            deletedRanges: active.pendingRanges,
            deletedTexts: active.pendingTexts,
            deletedVisibleCharacterCount: active.pendingVisibleCharacterCount,
            deletedRatio: deletedRatio,
            strength: strength,
            replacementText: active.replacementText,
            reason: reason
        )
        active.pendingRanges = []
        active.pendingTexts = []
        active.pendingVisibleCharacterCount = 0
        active.replacementText = nil
        if active.currentText.isEmpty || reason != "delete_idle" {
            activeSpan = nil
        } else {
            activeSpan = active
        }
        lock.unlock()
        guard let recorder else {
            return
        }
        Task.detached(priority: .utility) {
            await recorder.recordAcceptedFeedback(record)
        }
    }

    private static func deletedRange(
        for selectedRange: NSRange,
        activeStart: Int,
        activeEnd: Int,
        currentText: String
    ) -> NSRange? {
        guard selectedRange.location != NSNotFound,
              selectedRange.length != NSNotFound,
              selectedRange.location >= activeStart,
              selectedRange.location <= activeEnd else {
            return nil
        }
        if selectedRange.length > 0 {
            guard selectedRange.location + selectedRange.length <= activeEnd else {
                return nil
            }
            return selectedRange
        }
        guard selectedRange.location > activeStart else {
            return nil
        }
        let relativeIndex = selectedRange.location - activeStart - 1
        guard relativeIndex >= 0,
              relativeIndex < (currentText as NSString).length else {
            return nil
        }
        let composedRange = (currentText as NSString)
            .rangeOfComposedCharacterSequence(at: relativeIndex)
        return NSRange(
            location: activeStart + composedRange.location,
            length: composedRange.length
        )
    }

    private static func isKnownCollapsedRange(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length == 0
    }

    private static func strength(
        deletedRatio: Double,
        visibleCharacterCount: Int
    ) -> AIAcceptedFeedbackStrength {
        if deletedRatio >= 0.8 || visibleCharacterCount >= 12 {
            return .strong
        }
        if deletedRatio >= 0.35 || visibleCharacterCount >= 4 {
            return .medium
        }
        return .weak
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
