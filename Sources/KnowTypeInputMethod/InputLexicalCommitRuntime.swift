import Foundation
import KnowTypeAI

struct InputLexicalSelectionContext: Sendable, Equatable {
    var text: String
    var rawInput: String
    var appBundleID: String?
    var schemaID: String
    var compositionID: Int
}

struct InputLexicalCommitContext: Sendable, Equatable {
    var text: String
    var schemaID: String
    var compositionID: Int
}

protocol InputLexicalProfileManaging: Sendable {
    func lexicalContextSnapshot(
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    ) -> LexicalContextSnapshot?
    func scheduleRefresh(
        reason: String,
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    )
    func cancelRefresh()
}

extension LexicalProfileRuntime: InputLexicalProfileManaging {}

final class InputLexicalCommitRuntime: @unchecked Sendable {
    static let defaultMaxRecentCommits = 32

    private let selectionHistoryRuntime: InputSelectionHistoryRuntime
    private let lexicalProfileRuntime: any InputLexicalProfileManaging
    private let maxRecentCommits: Int
    private var recentLexicalCommits: [String] = []

    init(
        selectionHistoryRuntime: InputSelectionHistoryRuntime,
        lexicalProfileRuntime: any InputLexicalProfileManaging,
        maxRecentCommits: Int = InputLexicalCommitRuntime.defaultMaxRecentCommits
    ) {
        self.selectionHistoryRuntime = selectionHistoryRuntime
        self.lexicalProfileRuntime = lexicalProfileRuntime
        self.maxRecentCommits = max(0, maxRecentCommits)
    }

    func recordSelection(context: InputLexicalSelectionContext) -> InputRuntimeEvent? {
        guard let event = selectionHistoryRuntime.recordSelection(
            context.text,
            rawInput: context.rawInput,
            appBundleID: context.appBundleID,
            schemaID: context.schemaID,
            compositionID: context.compositionID
        ) else {
            return nil
        }
        scheduleLexicalProfileRefresh(reason: "selection", schemaID: context.schemaID)
        return event
    }

    func recordCommit(context: InputLexicalCommitContext) -> InputRuntimeEvent? {
        let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        recentLexicalCommits.append(trimmed)
        if recentLexicalCommits.count > maxRecentCommits {
            recentLexicalCommits.removeFirst(recentLexicalCommits.count - maxRecentCommits)
        }
        scheduleLexicalProfileRefresh(reason: "commit", schemaID: context.schemaID)
        return .compositionCommitted(
            text: trimmed,
            schemaID: context.schemaID,
            compositionID: context.compositionID
        )
    }

    func lexicalContextSnapshot(schemaID: String) -> LexicalContextSnapshot? {
        lexicalProfileRuntime.lexicalContextSnapshot(
            schemaID: schemaID,
            recentCommits: recentLexicalCommits,
            selectionHistory: selectionHistoryRuntime.recentSelectionHistory
        )
    }

    func flushSelectionHistory() {
        selectionHistoryRuntime.flush()
    }

    func cancelRefresh() {
        lexicalProfileRuntime.cancelRefresh()
    }

    private func scheduleLexicalProfileRefresh(reason: String, schemaID: String) {
        lexicalProfileRuntime.scheduleRefresh(
            reason: reason,
            schemaID: schemaID,
            recentCommits: recentLexicalCommits,
            selectionHistory: selectionHistoryRuntime.recentSelectionHistory
        )
    }
}
