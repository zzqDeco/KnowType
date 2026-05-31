import CryptoKit
import Foundation
import KnowTypeAI
import KnowTypeCore

final class LexicalProfileRuntime: @unchecked Sendable {
    private let store: LexicalProfileStore
    private let rimeMaintenanceService: (any RimeUserDBTextSnapshotProviding)?
    private let acceptedLearningProvider: (any AIAcceptedLearningSnapshotProviding)?
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let builder = LexicalContextBuilder()
    private let refreshGate: LexicalProfileRefreshGate
    private let latestContextLock = NSLock()
    private var refreshTask: Task<Void, Never>?
    private var latestRefreshContext: LexicalProfileRefreshContext?
    private var acceptedSummaryObserver: (observer: any AIAcceptedLearningSummaryObserving, id: UUID)?

    init(
        store: LexicalProfileStore,
        rimeMaintenanceService: (any RimeUserDBTextSnapshotProviding)?,
        acceptedLearningProvider: (any AIAcceptedLearningSnapshotProviding)? = nil,
        diagnosticSink: any AIRecommendationDiagnosticSink,
        refreshGate: LexicalProfileRefreshGate
    ) {
        self.store = store
        self.rimeMaintenanceService = rimeMaintenanceService
        self.acceptedLearningProvider = acceptedLearningProvider
        self.diagnosticSink = diagnosticSink
        self.refreshGate = refreshGate
        if let observer = acceptedLearningProvider as? any AIAcceptedLearningSummaryObserving {
            let id = observer.addSummaryReadyObserver { [weak self] event in
                self?.handleAcceptedSummaryReady(event)
            }
            acceptedSummaryObserver = (observer, id)
        }
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: .lexicalProfileLoad,
                reason: store.currentSnapshot() == nil ? "empty" : "loaded"
            )
        )
    }

    deinit {
        if let acceptedSummaryObserver {
            acceptedSummaryObserver.observer.removeSummaryReadyObserver(acceptedSummaryObserver.id)
        }
    }

    func currentProfile() -> PersistentLexicalProfile? {
        store.currentProfile()
    }

    func lexicalContextSnapshot(
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    ) -> LexicalContextSnapshot? {
        let persisted = store.currentProfile()
        let persistedLexicalContext = persisted?.schemaID == schemaID ? persisted?.lexicalContext : nil
        let acceptedSummary = acceptedLearningProvider?.snapshot(schemaID: schemaID)
        return builder.snapshot(
            recentCommits: recentCommits,
            selectionHistory: selectionHistory,
            acceptedAITerms: acceptedSummary?.termProfile ?? [],
            acceptedAIRecentCommits: acceptedSummary?.recentAcceptedCommits ?? [],
            acceptedAISourceSummary: acceptedSummary?.sourceSummary ?? [],
            persistentTerms: persistedLexicalContext?.terms ?? [],
            persistentRecentCommits: persistedLexicalContext?.recentCommits ?? [],
            persistentSourceSummary: persistedLexicalContext?.sourceSummary ?? []
        )
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func scheduleRefresh(
        reason: String,
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    ) {
        let context = LexicalProfileRefreshContext(
            schemaID: schemaID,
            recentCommits: recentCommits,
            selectionHistory: selectionHistory
        )
        latestContextLock.lock()
        latestRefreshContext = context
        latestContextLock.unlock()

        guard let rimeMaintenanceService else {
            return
        }
        let generation = refreshGate.next()
        cancelRefresh()

        let store = store
        let diagnosticSink = diagnosticSink
        let builder = builder
        let parser = RimeUserDBTextParser(maxTerms: 64)
        let refreshGate = refreshGate
        let acceptedLearningProvider = acceptedLearningProvider

        let task = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .rimeUserDBSnapshotLoadStart,
                    candidateCount: recentCommits.count + selectionHistory.count,
                    reason: reason
                )
            )
            do {
                let snapshot = try await rimeMaintenanceService.userDBTextSnapshot(schemaID: schemaID)
                guard !Task.isCancelled else {
                    return
                }
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .rimeUserDBSnapshotLoadEnd,
                        reason: "path_hash=\(Self.pathHash(snapshot.fileURL.path))"
                    )
                )
                let terms = parser.parse(snapshot)
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .rimeUserDBParse,
                        candidateCount: terms.count,
                        reason: "schema=\(snapshot.schemaID)"
                    )
                )
                let acceptedSummary = acceptedLearningProvider?.snapshot(schemaID: schemaID)
                guard let lexical = builder.snapshot(
                    recentCommits: recentCommits,
                    selectionHistory: selectionHistory,
                    acceptedAITerms: acceptedSummary?.termProfile ?? [],
                    acceptedAIRecentCommits: acceptedSummary?.recentAcceptedCommits ?? [],
                    acceptedAISourceSummary: acceptedSummary?.sourceSummary ?? [],
                    persistentTerms: terms,
                    persistentSourceSummary: [
                        "rime-userdb-snapshot: \(Self.pathHash(snapshot.fileURL.path))"
                    ]
                ) else {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .lexicalProfileFallback,
                            candidateCount: 0,
                            reason: "empty_after_parse"
                        )
                    )
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                let transaction = try store.prepareSave(
                    snapshot: lexical,
                    schemaID: schemaID,
                    rimeSnapshotURL: snapshot.fileURL,
                    rimeSnapshotModifiedAt: snapshot.modifiedAt
                )
                guard !Task.isCancelled else {
                    store.discardPreparedSave(transaction)
                    return
                }
                guard let _ = try store.commitPreparedSaveIfCurrent(transaction, shouldCommit: {
                    !Task.isCancelled && refreshGate.isCurrent(generation)
                }) else {
                    return
                }
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .lexicalProfileUpdated,
                        candidateCount: lexical.terms.count,
                        reason: "generation=\(generation)"
                    )
                )
            } catch {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .lexicalProfileFallback,
                        reason: String(describing: type(of: error))
                    )
                )
            }
        }
        refreshTask = task
    }

    private func handleAcceptedSummaryReady(_ event: AIAcceptedLearningSummaryReadyEvent) {
        latestContextLock.lock()
        let context = latestRefreshContext
        latestContextLock.unlock()
        guard let context,
              context.schemaID == event.schemaID else {
            return
        }
        scheduleRefresh(
            reason: "accepted-ai-summary",
            schemaID: context.schemaID,
            recentCommits: context.recentCommits,
            selectionHistory: context.selectionHistory
        )
    }

    private static func pathHash(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct LexicalProfileRefreshContext: Sendable {
    var schemaID: String
    var recentCommits: [String]
    var selectionHistory: [String]
}
