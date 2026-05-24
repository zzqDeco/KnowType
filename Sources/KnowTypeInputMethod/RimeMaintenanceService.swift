import Foundation
import KnowTypeAI

protocol RimeUserDBTextSnapshotSyncProviding: RimeUserDBTextSnapshotProviding {
    func syncedUserDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot
}

struct RimeMaintenancePolicy: Sendable, Equatable {
    var idleInterval: TimeInterval
    var minimumSyncInterval: TimeInterval

    static let standard = RimeMaintenancePolicy(
        idleInterval: 60,
        minimumSyncInterval: 10 * 60
    )
}

actor RimeMaintenanceService: RimeUserDBTextSnapshotProviding {
    private let snapshotProvider: any RimeUserDBTextSnapshotSyncProviding
    private var lastSyncAt: Date?

    init(snapshotProvider: any RimeUserDBTextSnapshotSyncProviding) {
        self.snapshotProvider = snapshotProvider
    }

    func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        try await existingUserDBSnapshot(schemaID: schemaID)
    }

    func existingUserDBSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        try await snapshotProvider.userDBTextSnapshot(schemaID: schemaID)
    }

    func syncUserDataIfIdle(
        schemaID: String,
        lastInputAt: Date,
        now: Date = Date(),
        policy: RimeMaintenancePolicy = .standard
    ) async throws -> RimeUserDBTextSnapshot {
        guard now.timeIntervalSince(lastInputAt) >= policy.idleInterval else {
            return try await existingUserDBSnapshot(schemaID: schemaID)
        }
        if let lastSyncAt,
           now.timeIntervalSince(lastSyncAt) < policy.minimumSyncInterval {
            return try await existingUserDBSnapshot(schemaID: schemaID)
        }
        let snapshot = try await snapshotProvider.syncedUserDBTextSnapshot(schemaID: schemaID)
        lastSyncAt = now
        return snapshot
    }
}
