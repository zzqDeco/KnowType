import Foundation
import KnowTypeCore

final class InputSelectionHistoryRuntime: @unchecked Sendable {
    private let persistence: (any InputControllerUserSelectionHistoryPersisting)?
    private let maxEntries: Int
    private var persistedHistory: [String]
    private var recentSelections: [String] = []

    init(
        persistence: (any InputControllerUserSelectionHistoryPersisting)?,
        maxEntries: Int
    ) {
        self.persistence = persistence
        self.maxEntries = max(0, maxEntries)
        self.persistedHistory = persistence?.loadHistory(maxEntries: self.maxEntries) ?? []
    }

    var recentSelectionHistory: [String] {
        recentSelections
    }

    @discardableResult
    func recordSelection(
        _ text: String,
        rawInput: String,
        appBundleID: String?,
        schemaID: String,
        compositionID: Int
    ) -> InputRuntimeEvent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !TextProtection.requiresNoCorrection(trimmed, appBundleID: appBundleID),
              !TextProtection.requiresNoCorrection(rawInput, appBundleID: appBundleID) else {
            return nil
        }

        recordRecentSelection(trimmed)
        recordPersistedSelection(trimmed)
        return .candidateSelected(
            text: trimmed,
            schemaID: schemaID,
            compositionID: compositionID
        )
    }

    func flush() {
        persistence?.flushHistory(persistedHistory, maxEntries: maxEntries)
    }

    private func recordRecentSelection(_ text: String) {
        recentSelections.append(text)
        trimToMaxEntries(&recentSelections)
    }

    private func recordPersistedSelection(_ text: String) {
        if let persistence {
            persistedHistory = persistence.recordSelection(
                text,
                currentHistory: persistedHistory,
                maxEntries: maxEntries
            )
            return
        }

        persistedHistory.append(text)
        trimToMaxEntries(&persistedHistory)
    }

    private func trimToMaxEntries(_ history: inout [String]) {
        guard maxEntries > 0 else {
            history.removeAll()
            return
        }
        if history.count > maxEntries {
            history.removeFirst(history.count - maxEntries)
        }
    }
}
