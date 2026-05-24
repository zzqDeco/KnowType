import CryptoKit
import Foundation
import KnowTypeAI
import KnowTypeCore

final class LexicalProfileRuntime: @unchecked Sendable {
    private let store: LexicalProfileStore
    private let rimeMaintenanceService: (any RimeUserDBTextSnapshotProviding)?
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let builder = LexicalContextBuilder()
    private let refreshGate: LexicalProfileRefreshGate
    private var refreshTask: Task<Void, Never>?

    init(
        store: LexicalProfileStore,
        rimeMaintenanceService: (any RimeUserDBTextSnapshotProviding)?,
        diagnosticSink: any AIRecommendationDiagnosticSink,
        refreshGate: LexicalProfileRefreshGate
    ) {
        self.store = store
        self.rimeMaintenanceService = rimeMaintenanceService
        self.diagnosticSink = diagnosticSink
        self.refreshGate = refreshGate
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: .lexicalProfileLoad,
                reason: store.currentSnapshot() == nil ? "empty" : "loaded"
            )
        )
    }

    func currentProfile() -> PersistentLexicalProfile? {
        store.currentProfile()
    }

    func lexicalContextSnapshot(
        schemaID: String,
        rimeCandidates: [String],
        recentCommits: [String],
        selectionHistory: [String]
    ) -> LexicalContextSnapshot? {
        let persisted = store.currentProfile()
        let persistedLexicalContext = persisted?.schemaID == schemaID ? persisted?.lexicalContext : nil
        return builder.snapshot(
            rimeCandidates: rimeCandidates,
            recentCommits: recentCommits,
            selectionHistory: selectionHistory,
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
                guard let lexical = builder.snapshot(
                    recentCommits: recentCommits,
                    selectionHistory: selectionHistory,
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

    private static func pathHash(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
