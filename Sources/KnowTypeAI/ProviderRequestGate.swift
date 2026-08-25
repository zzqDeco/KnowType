import CryptoKit
import Darwin
import Foundation
import KnowTypeProviders
import OSLog

public enum ProviderRequestFailureClass: String, Codable, Sendable, Equatable {
    case transport
    case timeout
    case server5xx = "5xx"
    case auth
    case rateLimit = "429"
    case invalidOutput
    case localCommit
}

public enum ProviderRequestGateError: Error, Sendable, Equatable {
    case busy
    case cooldown(deadline: Date, failureClass: ProviderRequestFailureClass)
    case staleGeneration
}

enum ProviderRequestGatePersistenceError: Error, Sendable, Equatable {
    case blocked
}

enum ProviderRequestGatePreflightState: Sendable, Equatable {
    case available
    case busy
    case cooldown(deadline: Date, failureClass: ProviderRequestFailureClass)
    case staleGeneration
    case persistenceBlocked(retryAt: Date)
}

final class ProviderRequestGateTestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failedPermissionChangesRemaining = 0
    private var failedReadsRemaining = 0
    private var failedWritesRemaining = 0
    private var admittedAttempts = 0
    private var preflightChecks = 0
    private var rejectedTransportStarts = 0
    private var persistenceBlocks = 0
    private var persistenceRecoveryProbes = 0
    private var persistenceRecoveries = 0

    var admittedAttemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return admittedAttempts
    }

    var preflightCheckCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return preflightChecks
    }

    var rejectedTransportStartCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rejectedTransportStarts
    }

    var persistenceBlockCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistenceBlocks
    }

    var persistenceRecoveryProbeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistenceRecoveryProbes
    }

    var persistenceRecoveryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return persistenceRecoveries
    }

    func failNextPermissionChanges(_ count: Int) {
        lock.lock()
        failedPermissionChangesRemaining = max(0, count)
        lock.unlock()
    }

    func failNextReads(_ count: Int) {
        lock.lock()
        failedReadsRemaining = max(0, count)
        lock.unlock()
    }

    func failNextWrites(_ count: Int) {
        lock.lock()
        failedWritesRemaining = max(0, count)
        lock.unlock()
    }

    fileprivate func recordAttemptAdmission() {
        lock.lock()
        admittedAttempts += 1
        lock.unlock()
    }

    fileprivate func recordPreflightCheck() {
        lock.lock()
        preflightChecks += 1
        lock.unlock()
    }

    fileprivate func recordRejectedTransportStart() {
        lock.lock()
        rejectedTransportStarts += 1
        lock.unlock()
    }

    fileprivate func recordPersistenceBlock() {
        lock.lock()
        persistenceBlocks += 1
        lock.unlock()
    }

    fileprivate func recordPersistenceRecoveryProbe() {
        lock.lock()
        persistenceRecoveryProbes += 1
        lock.unlock()
    }

    fileprivate func recordPersistenceRecovery() {
        lock.lock()
        persistenceRecoveries += 1
        lock.unlock()
    }

    fileprivate func shouldFailPermissionChange() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedPermissionChangesRemaining > 0 else { return false }
        failedPermissionChangesRemaining -= 1
        return true
    }

    fileprivate func shouldFailRead() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedReadsRemaining > 0 else { return false }
        failedReadsRemaining -= 1
        return true
    }

    fileprivate func shouldFailWrite() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedWritesRemaining > 0 else { return false }
        failedWritesRemaining -= 1
        return true
    }
}

private enum ProviderRequestTimeoutOwnership: Sendable {
    case beforeTransport
    case transportStarted
}

private final class ProviderRequestAttemptFence: @unchecked Sendable {
    private enum Phase: Equatable {
        case admitted
        case transportStarted
        case timeoutOwnedBeforeTransport
        case timeoutOwnedTransport
        case aborted
    }

    private let lock = NSLock()
    private var phase = Phase.admitted

    func beginTransport() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .admitted:
            phase = .transportStarted
            return true
        case .transportStarted, .timeoutOwnedBeforeTransport,
             .timeoutOwnedTransport, .aborted:
            return false
        }
    }

    func claimTimeoutOwnership(
        _ claimingTimeout: @Sendable () -> Bool
    ) -> ProviderRequestTimeoutOwnership? {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .admitted:
            guard claimingTimeout() else { return nil }
            phase = .timeoutOwnedBeforeTransport
            return .beforeTransport
        case .transportStarted:
            guard claimingTimeout() else { return nil }
            phase = .timeoutOwnedTransport
            return .transportStarted
        case .timeoutOwnedBeforeTransport, .timeoutOwnedTransport, .aborted:
            return nil
        }
    }

    func abortBeforeTransportIfPossible() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .admitted:
            phase = .aborted
            return true
        case .timeoutOwnedBeforeTransport, .aborted:
            return true
        case .transportStarted, .timeoutOwnedTransport:
            return false
        }
    }
}

private final class ProviderRequestAttemptCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let callback: @Sendable () async -> Void
    private var completed = false

    init(callback: @escaping @Sendable () async -> Void) {
        self.callback = callback
    }

    func run() async {
        guard claim() else { return }
        await callback()
    }

    private func claim() -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        lock.unlock()
        return true
    }
}

public actor ProviderRequestGate {
    public static let shared = ProviderRequestGate(persistenceURL: defaultPersistenceURL())

    private static let maximumPersistenceByteCount = 64 * 1_024
    private static let maximumPersistedEntryCount = 256
    private static let persistenceRecoveryInitialDelay: TimeInterval = 5
    private static let persistenceRecoveryMaximumDelay: TimeInterval = 60
    private static let logger = Logger(
        subsystem: "com.knowtype.inputmethod.KnowType",
        category: "ai"
    )

    private enum PersistenceRecoveryOperation: String {
        case reload
        case rewrite
    }

    private enum PersistenceState {
        case uninitialized
        case available
        case blocked(
            retryAt: Date,
            failureCount: Int,
            operation: PersistenceRecoveryOperation
        )
        case probing(
            failureCount: Int,
            operation: PersistenceRecoveryOperation
        )
    }

    private struct Attempt: Sendable {
        let id: UUID
        let identityHash: String
        let generation: UInt64
        let fence: ProviderRequestAttemptFence
        let completion: ProviderRequestAttemptCompletion
    }

    private struct State {
        var generation: UInt64 = 0
        var activeAttemptID: UUID?
        var timedOutAttemptID: UUID?
        var failureCount = 0
        var cooldownUntil: Date?
        var failureClass: ProviderRequestFailureClass?

        var inFlight: Bool { activeAttemptID != nil }
    }

    private struct PersistedEntry: Codable {
        var identityHash: String
        var deadline: Date
        var failureClass: ProviderRequestFailureClass
        var failureCount: Int
    }

    private struct PersistedState: Codable {
        var entries: [PersistedEntry]
    }

    private struct LoadedPersistedState {
        var entries: [String: PersistedEntry]
        var needsRewrite: Bool
    }

    private struct PersistenceOperationFailure: Error {
        var operation: PersistenceRecoveryOperation
    }

    private struct AvailabilityWaiter {
        var continuation: CheckedContinuation<Void, Never>
        var deadlineTask: Task<Void, Never>?
    }

    private var states: [String: State] = [:]
    private var activeAttempts: [String: Attempt] = [:]
    private let now: @Sendable () -> Date
    private let persistenceURL: URL?
    private let fileManager: FileManager
    private let testProbe: ProviderRequestGateTestProbe?
    private let afterAttemptAdmission: (@Sendable () async -> Void)?
    private var persistedEntries: [String: PersistedEntry] = [:]
    private var pendingPersistedEntryClears: Set<String> = []
    private var persistenceState: PersistenceState = .uninitialized
    private var lastForcedPersistenceRecoveryGeneration: UInt64?
    private var availabilityWaiters: [String: [UUID: AvailabilityWaiter]] = [:]

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        persistenceURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.now = now
        self.persistenceURL = persistenceURL
        self.fileManager = fileManager
        self.testProbe = nil
        self.afterAttemptAdmission = nil
    }

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        persistenceURL: URL? = nil,
        fileManager: FileManager = .default,
        testProbe: ProviderRequestGateTestProbe,
        afterAttemptAdmission: (@Sendable () async -> Void)? = nil
    ) {
        self.now = now
        self.persistenceURL = persistenceURL
        self.fileManager = fileManager
        self.testProbe = testProbe
        self.afterAttemptAdmission = afterAttemptAdmission
    }

    public static func identityHash(_ identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func invalidate(providerIdentity: String, generation: UInt64) async {
        await invalidate(
            providerIdentity: providerIdentity,
            expectedGeneration: generation,
            newGeneration: generation &+ 1
        )
    }

    func invalidate(
        providerIdentity: String,
        expectedGeneration: UInt64,
        newGeneration: UInt64
    ) async {
        let key = Self.identityHash(providerIdentity)
        let knownGeneration = states[key, default: State()].generation
        _ = ensurePersistenceAvailable(
            forceRecovery: newGeneration > knownGeneration,
            identityHash: key,
            generation: newGeneration
        )
        var state = state(for: key)
        guard expectedGeneration >= state.generation else { return }
        let abortedCompletion: ProviderRequestAttemptCompletion?
        if let activeAttempt = activeAttempts[key] {
            abortedCompletion = closePreTransportAttemptIfMatching(
                activeAttempt,
                state: &state
            )
        } else {
            abortedCompletion = nil
        }
        state.generation = newGeneration
        state.cooldownUntil = nil
        state.failureClass = nil
        state.failureCount = 0
        state.timedOutAttemptID = nil
        states[key] = state
        clearPersistedEntry(for: key)
        resumeAvailabilityWaiters(for: key)
        await abortedCompletion?.run()
    }

    public func cooldownDeadline(providerIdentity: String, generation: UInt64) -> Date? {
        let key = Self.identityHash(providerIdentity)
        guard ensurePersistenceAvailable(
            forceRecovery: generation > states[key, default: State()].generation,
            identityHash: key,
            generation: generation
        ) else { return nil }
        let state = state(for: key)
        guard isPersistenceAvailable else { return nil }
        guard state.generation <= generation else { return nil }
        guard let deadline = state.cooldownUntil, deadline > now() else {
            if persistedEntries[key] != nil { clearPersistedEntry(for: key) }
            return nil
        }
        return deadline
    }

    func preflight(
        providerIdentity: String,
        generation: UInt64
    ) -> ProviderRequestGatePreflightState {
        testProbe?.recordPreflightCheck()
        let key = Self.identityHash(providerIdentity)
        guard ensurePersistenceAvailable(
            forceRecovery: generation > states[key, default: State()].generation,
            identityHash: key,
            generation: generation
        ) else {
            return .persistenceBlocked(retryAt: persistenceRetryAt)
        }
        var state = state(for: key)
        guard isPersistenceAvailable else {
            return .persistenceBlocked(retryAt: persistenceRetryAt)
        }
        if states[key] == nil, persistedEntries[key] != nil {
            state.generation = generation
        }
        if generation < state.generation { return .staleGeneration }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            state.cooldownUntil = nil
            state.failureClass = nil
            state.timedOutAttemptID = nil
            states[key] = state
            clearPersistedEntry(for: key)
            guard isPersistenceAvailable else {
                return .persistenceBlocked(retryAt: persistenceRetryAt)
            }
        }
        if state.inFlight { return .busy }
        if let deadline = state.cooldownUntil, deadline > now() {
            return .cooldown(
                deadline: deadline,
                failureClass: state.failureClass ?? .transport
            )
        }
        return .available
    }

    func persistencePreflight() -> ProviderRequestGatePreflightState {
        testProbe?.recordPreflightCheck()
        guard ensurePersistenceAvailable() else {
            return .persistenceBlocked(retryAt: persistenceRetryAt)
        }
        return .available
    }

    public func waitForAvailability(providerIdentity: String, generation: UInt64) async {
        let key = Self.identityHash(providerIdentity)
        while !Task.isCancelled {
            guard ensurePersistenceAvailable(
                forceRecovery: generation > states[key, default: State()].generation,
                identityHash: key,
                generation: generation
            ) else { return }
            let state = state(for: key)
            guard isPersistenceAvailable else { return }
            if generation < state.generation {
                return
            }
            if !state.inFlight &&
                (state.cooldownUntil == nil || state.cooldownUntil ?? .distantPast <= now()) {
                if persistedEntries[key] != nil { clearPersistedEntry(for: key) }
                return
            }
            let waiterID = UUID()
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    registerAvailabilityWaiter(
                        continuation,
                        for: key,
                        id: waiterID,
                        generation: generation
                    )
                }
            }, onCancel: {
                Task { await self.cancelAvailabilityWaiter(for: key, id: waiterID) }
            })
        }
    }

    public func execute<T: Sendable>(
        providerIdentity: String,
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let fence = ProviderRequestAttemptFence()
        let completion = ProviderRequestAttemptCompletion(callback: {})
        let attempt = try beginAttempt(
            providerIdentity: providerIdentity,
            generation: generation,
            fence: fence,
            completion: completion
        )
        return try await withTaskCancellationHandler {
            do {
                await afterAttemptAdmission?()
                try Task.checkCancellation()
                guard attempt.fence.beginTransport() else { throw CancellationError() }
                return try await perform(attempt: attempt, operation: operation)
            } catch {
                if Self.isCancellation(error) {
                    if attempt.fence.abortBeforeTransportIfPossible() {
                        abortAttempt(attempt)
                    }
                }
                throw error
            }
        } onCancel: {
            guard attempt.fence.abortBeforeTransportIfPossible() else { return }
            Task { await self.abortAttempt(attempt) }
        }
    }

    func executeWithHardTimeout<T: Sendable>(
        providerIdentity: String,
        generation: UInt64,
        timeoutNanoseconds: UInt64,
        onAttemptCompletion: @escaping @Sendable () async -> Void = {},
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let completion = ProviderRequestAttemptCompletion(callback: onAttemptCompletion)
        let fence = ProviderRequestAttemptFence()
        let attempt: Attempt
        do {
            attempt = try beginAttempt(
                providerIdentity: providerIdentity,
                generation: generation,
                fence: fence,
                completion: completion
            )
        } catch {
            await completion.run()
            throw error
        }
        let afterAttemptAdmission = self.afterAttemptAdmission
        let testProbe = self.testProbe
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                return try await withTimeout(
                    nanoseconds: timeoutNanoseconds,
                    onTimeout: { claimTimeout in
                        guard let ownership = try await self.recordTimeout(
                            for: attempt,
                            claimingTimeout: claimTimeout
                        ) else { return false }
                        if case .beforeTransport = ownership {
                            await completion.run()
                        }
                        return true
                    }
                ) {
                    await afterAttemptAdmission?()
                    guard attempt.fence.beginTransport() else {
                        testProbe?.recordRejectedTransportStart()
                        throw CancellationError()
                    }
                    do {
                        let value = try await self.perform(attempt: attempt, operation: operation)
                        await completion.run()
                        return value
                    } catch {
                        await completion.run()
                        throw error
                    }
                }
            } catch {
                if Self.isCancellation(error) {
                    if attempt.fence.abortBeforeTransportIfPossible() {
                        abortAttempt(attempt)
                        await completion.run()
                    }
                }
                throw error
            }
        } onCancel: {
            guard attempt.fence.abortBeforeTransportIfPossible() else { return }
            Task {
                await self.abortAttempt(attempt)
                await completion.run()
            }
        }
    }

    private func beginAttempt(
        providerIdentity: String,
        generation: UInt64,
        fence: ProviderRequestAttemptFence,
        completion: ProviderRequestAttemptCompletion
    ) throws -> Attempt {
        let key = Self.identityHash(providerIdentity)
        guard ensurePersistenceAvailable(
            forceRecovery: generation > states[key, default: State()].generation,
            identityHash: key,
            generation: generation
        ) else {
            throw ProviderRequestGatePersistenceError.blocked
        }
        var state = state(for: key)
        guard isPersistenceAvailable else {
            throw ProviderRequestGatePersistenceError.blocked
        }
        if states[key] == nil, persistedEntries[key] != nil {
            state.generation = generation
        }
        if generation < state.generation { throw ProviderRequestGateError.staleGeneration }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            state.cooldownUntil = nil
            state.failureClass = nil
            state.timedOutAttemptID = nil
            clearPersistedEntry(for: key)
            guard isPersistenceAvailable else {
                throw ProviderRequestGatePersistenceError.blocked
            }
        }
        if state.inFlight { throw ProviderRequestGateError.busy }
        if let deadline = state.cooldownUntil, deadline > now() {
            throw ProviderRequestGateError.cooldown(
                deadline: deadline,
                failureClass: state.failureClass ?? .transport
            )
        }
        let attempt = Attempt(
            id: UUID(),
            identityHash: key,
            generation: generation,
            fence: fence,
            completion: completion
        )
        state.activeAttemptID = attempt.id
        state.timedOutAttemptID = nil
        states[key] = state
        activeAttempts[key] = attempt
        testProbe?.recordAttemptAdmission()
        return attempt
    }

    private func perform<T: Sendable>(
        attempt: Attempt,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let result: Result<T, Error>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let value):
            return try finishSuccess(value, attempt: attempt)
        case .failure(let error):
            throw finishFailure(error, attempt: attempt)
        }
    }

    private func closePreTransportAttemptIfMatching(
        _ attempt: Attempt,
        state: inout State
    ) -> ProviderRequestAttemptCompletion? {
        guard state.activeAttemptID == attempt.id,
              activeAttempts[attempt.identityHash]?.id == attempt.id,
              attempt.fence.abortBeforeTransportIfPossible() else { return nil }
        state.activeAttemptID = nil
        if state.timedOutAttemptID == attempt.id {
            state.timedOutAttemptID = nil
        }
        activeAttempts[attempt.identityHash] = nil
        return attempt.completion
    }

    private func removeActiveAttemptIfMatching(_ attempt: Attempt) {
        guard activeAttempts[attempt.identityHash]?.id == attempt.id else { return }
        activeAttempts[attempt.identityHash] = nil
    }

    private func abortAttempt(_ attempt: Attempt) {
        var state = states[attempt.identityHash, default: State()]
        guard state.timedOutAttemptID != attempt.id else { return }
        guard closePreTransportAttemptIfMatching(attempt, state: &state) != nil else { return }
        states[attempt.identityHash] = state
        resumeAvailabilityWaiters(for: attempt.identityHash)
    }

    private func recordTimeout(
        for attempt: Attempt,
        claimingTimeout: @Sendable () -> Bool
    ) async throws -> ProviderRequestTimeoutOwnership? {
        var state = states[attempt.identityHash, default: State()]
        guard state.generation == attempt.generation else {
            let completion = closePreTransportAttemptIfMatching(attempt, state: &state)
            if completion != nil {
                states[attempt.identityHash] = state
                resumeAvailabilityWaiters(for: attempt.identityHash)
            }
            await completion?.run()
            throw ProviderRequestGateError.staleGeneration
        }
        guard state.activeAttemptID == attempt.id else { return nil }
        guard state.timedOutAttemptID != attempt.id,
              let ownership = attempt.fence.claimTimeoutOwnership(claimingTimeout) else { return nil }

        state.failureCount = min(16, state.failureCount + 1)
        state.failureClass = .timeout
        state.cooldownUntil = now().addingTimeInterval(
            Self.cooldownSeconds(
                failureClass: .timeout,
                failureCount: state.failureCount,
                retryAfter: nil
            )
        )
        switch ownership {
        case .beforeTransport:
            state.activeAttemptID = nil
            state.timedOutAttemptID = nil
            removeActiveAttemptIfMatching(attempt)
        case .transportStarted:
            state.timedOutAttemptID = attempt.id
        }
        states[attempt.identityHash] = state
        persist(state, for: attempt.identityHash)
        if case .beforeTransport = ownership {
            resumeAvailabilityWaiters(for: attempt.identityHash)
        }
        return ownership
    }

    private func finishSuccess<T: Sendable>(_ value: T, attempt: Attempt) throws -> T {
        var state = states[attempt.identityHash, default: State()]
        guard state.activeAttemptID == attempt.id else {
            throw ProviderRequestGateError.staleGeneration
        }
        state.activeAttemptID = nil
        removeActiveAttemptIfMatching(attempt)
        let timedOut = state.timedOutAttemptID == attempt.id
        state.timedOutAttemptID = nil
        guard state.generation == attempt.generation else {
            states[attempt.identityHash] = state
            resumeAvailabilityWaiters(for: attempt.identityHash)
            throw ProviderRequestGateError.staleGeneration
        }
        if timedOut {
            states[attempt.identityHash] = state
            persist(state, for: attempt.identityHash)
            resumeAvailabilityWaiters(for: attempt.identityHash)
            throw TimeoutError()
        }
        if let deadline = state.cooldownUntil, deadline > now() {
            states[attempt.identityHash] = state
            persist(state, for: attempt.identityHash)
            resumeAvailabilityWaiters(for: attempt.identityHash)
            return value
        }
        state.failureCount = 0
        state.cooldownUntil = nil
        state.failureClass = nil
        states[attempt.identityHash] = state
        clearPersistedEntry(for: attempt.identityHash)
        resumeAvailabilityWaiters(for: attempt.identityHash)
        return value
    }

    private func finishFailure(_ error: Error, attempt: Attempt) -> Error {
        var state = states[attempt.identityHash, default: State()]
        guard state.activeAttemptID == attempt.id else {
            return ProviderRequestGateError.staleGeneration
        }
        state.activeAttemptID = nil
        removeActiveAttemptIfMatching(attempt)
        let timedOut = state.timedOutAttemptID == attempt.id
        state.timedOutAttemptID = nil
        if state.generation != attempt.generation {
            states[attempt.identityHash] = state
            resumeAvailabilityWaiters(for: attempt.identityHash)
            return ProviderRequestGateError.staleGeneration
        }
        if timedOut {
            states[attempt.identityHash] = state
            persist(state, for: attempt.identityHash)
            resumeAvailabilityWaiters(for: attempt.identityHash)
            return TimeoutError()
        }
        if Task.isCancelled || Self.isCancellation(error) || Self.isStale(error) {
            states[attempt.identityHash] = state
            resumeAvailabilityWaiters(for: attempt.identityHash)
            return error
        }
        if error is ProviderRequestBudgetError {
            states[attempt.identityHash] = state
            resumeAvailabilityWaiters(for: attempt.identityHash)
            return error
        }
        let failureClass = Self.classify(error)
        state.failureCount = min(16, state.failureCount + 1)
        state.failureClass = failureClass
        state.cooldownUntil = now().addingTimeInterval(
            Self.cooldownSeconds(
                failureClass: failureClass,
                failureCount: state.failureCount,
                retryAfter: (error as? ProviderRateLimitError)?.retryAfterSeconds
            )
        )
        states[attempt.identityHash] = state
        persist(state, for: attempt.identityHash)
        resumeAvailabilityWaiters(for: attempt.identityHash)
        return error
    }

    public func recordLocalCommitFailure(providerIdentity: String, generation: UInt64) {
        recordFailure(
            providerIdentity: providerIdentity,
            generation: generation,
            failure: NSError(domain: "KnowType.ProviderRequestGate", code: 1),
            forcedClass: .localCommit
        )
    }

    public func recordFailure(
        providerIdentity: String,
        generation: UInt64,
        failure: Error,
        forcedClass: ProviderRequestFailureClass? = nil
    ) {
        let key = Self.identityHash(providerIdentity)
        guard ensurePersistenceAvailable(
            forceRecovery: generation > states[key, default: State()].generation,
            identityHash: key,
            generation: generation
        ) else { return }
        if failure is ProviderRequestBudgetError { return }
        var state = state(for: key)
        guard isPersistenceAvailable else { return }
        guard state.generation <= generation,
              !Self.isCancellation(failure),
              !Self.isStale(failure) else { return }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            clearPersistedEntry(for: key)
            guard isPersistenceAvailable else { return }
        }
        let failureClass = forcedClass ?? Self.classify(failure)
        state.failureCount = min(16, state.failureCount + 1)
        state.failureClass = failureClass
        state.cooldownUntil = now().addingTimeInterval(
            Self.cooldownSeconds(
                failureClass: failureClass,
                failureCount: state.failureCount,
                retryAfter: (failure as? ProviderRateLimitError)?.retryAfterSeconds
            )
        )
        states[key] = state
        persist(state, for: key)
        resumeAvailabilityWaiters(for: key)
    }

    private static func cooldownSeconds(
        failureClass: ProviderRequestFailureClass,
        failureCount: Int,
        retryAfter: TimeInterval?
    ) -> TimeInterval {
        if failureClass == .rateLimit, let retryAfter {
            return min(15 * 60, max(15, retryAfter))
        }
        let exponent = min(4, max(0, failureCount - 1))
        return min(15 * 60, 60 * pow(2, Double(exponent)))
    }

    private static func classify(_ error: Error) -> ProviderRequestFailureClass {
        if error is TimeoutError { return .timeout }
        if error is EnvironmentDocumentError { return .invalidOutput }
        if let rateLimit = error as? ProviderRateLimitError, rateLimit.statusCode == 429 {
            return .rateLimit
        }
        if case ProviderError.httpStatus(let status, _) = error {
            if status == 429 { return .rateLimit }
            if status == 401 || status == 403 { return .auth }
            if (500...599).contains(status) { return .server5xx }
            return .transport
        }
        if case ProviderError.missingAPIKey = error { return .auth }
        if case ProviderError.invalidResponse = error { return .invalidOutput }
        return .transport
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func isStale(_ error: Error) -> Bool {
        if error is ProviderRuntimeRegistryError { return true }
        guard let error = error as? ProviderRequestGateError else { return false }
        if case .staleGeneration = error { return true }
        return false
    }

    private static func defaultPersistenceURL() -> URL {
        AIUserDirectory.defaultDirectory().rootURL.appendingPathComponent("provider-request-gate.json")
    }

    private func state(for key: String) -> State {
        var state = states[key, default: State()]
        if state.cooldownUntil == nil, let persisted = persistedEntries[key] {
            if persisted.deadline > now(), persisted.failureCount >= 1, persisted.failureCount <= 16 {
                state.failureCount = persisted.failureCount
                state.cooldownUntil = persisted.deadline
                state.failureClass = persisted.failureClass
            } else {
                clearPersistedEntry(for: key)
            }
        }
        return state
    }

    private var isPersistenceAvailable: Bool {
        if case .available = persistenceState { return true }
        return false
    }

    private var persistenceRetryAt: Date {
        if case .blocked(let retryAt, _, _) = persistenceState {
            return retryAt
        }
        return now().addingTimeInterval(Self.persistenceRecoveryInitialDelay)
    }

    private func ensurePersistenceAvailable(
        forceRecovery: Bool = false,
        identityHash: String? = nil,
        generation: UInt64? = nil
    ) -> Bool {
        switch persistenceState {
        case .uninitialized:
            guard persistenceURL != nil else {
                persistenceState = .available
                return true
            }
            do {
                try reloadPersistedState()
                persistenceState = .available
                return true
            } catch let failure as PersistenceOperationFailure {
                if forceRecovery {
                    lastForcedPersistenceRecoveryGeneration = generation
                }
                blockPersistence(
                    operation: failure.operation,
                    previousFailureCount: 0,
                    identityHash: identityHash,
                    generation: generation
                )
                return false
            } catch {
                if forceRecovery {
                    lastForcedPersistenceRecoveryGeneration = generation
                }
                blockPersistence(
                    operation: .reload,
                    previousFailureCount: 0,
                    identityHash: identityHash,
                    generation: generation
                )
                return false
            }
        case .available:
            return true
        case .probing:
            return false
        case .blocked(let retryAt, let failureCount, let operation):
            let forcedGenerationIsNew = forceRecovery
                && generation != lastForcedPersistenceRecoveryGeneration
            guard forcedGenerationIsNew || now() >= retryAt else { return false }
            if forcedGenerationIsNew {
                lastForcedPersistenceRecoveryGeneration = generation
            }
            persistenceState = .probing(
                failureCount: failureCount,
                operation: operation
            )
            testProbe?.recordPersistenceRecoveryProbe()
            emitPersistenceDiagnostic(
                stage: "provider_gate_persistence_probing",
                operation: operation,
                failureCount: failureCount,
                retryAt: nil,
                identityHash: identityHash,
                generation: generation
            )
            do {
                switch operation {
                case .reload:
                    try reloadPersistedState()
                case .rewrite:
                    try writePersistedState()
                }
                persistenceState = .available
                testProbe?.recordPersistenceRecovery()
                emitPersistenceDiagnostic(
                    stage: "provider_gate_persistence_recovered",
                    operation: operation,
                    failureCount: failureCount,
                    retryAt: nil,
                    identityHash: identityHash,
                    generation: generation
                )
                resumeAllAvailabilityWaiters()
                return true
            } catch let failure as PersistenceOperationFailure {
                blockPersistence(
                    operation: failure.operation,
                    previousFailureCount: failureCount,
                    identityHash: identityHash,
                    generation: generation
                )
                return false
            } catch {
                blockPersistence(
                    operation: operation,
                    previousFailureCount: failureCount,
                    identityHash: identityHash,
                    generation: generation
                )
                return false
            }
        }
    }

    private func reloadPersistedState() throws {
        let loaded: LoadedPersistedState
        do {
            loaded = try readPersistedState()
        } catch {
            throw PersistenceOperationFailure(operation: .reload)
        }
        persistedEntries = loaded.entries
        let clearedEntryCount = pendingPersistedEntryClears.reduce(into: 0) { count, key in
            if persistedEntries.removeValue(forKey: key) != nil {
                count += 1
            }
        }
        guard loaded.needsRewrite || clearedEntryCount > 0 else {
            pendingPersistedEntryClears.removeAll()
            return
        }
        do {
            try writePersistedState()
        } catch {
            throw PersistenceOperationFailure(operation: .rewrite)
        }
    }

    private func readPersistedState() throws -> LoadedPersistedState {
        guard let persistenceURL else {
            return LoadedPersistedState(entries: [:], needsRewrite: false)
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: persistenceURL.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                throw ProviderRequestGatePersistenceError.blocked
            }
        } catch {
            if Self.isExplicitMissingFileError(error) {
                return LoadedPersistedState(entries: [:], needsRewrite: false)
            }
            throw error
        }
        try setSecurePermissions(of: persistenceURL)
        let data = try boundedData(
            at: persistenceURL,
            limit: Self.maximumPersistenceByteCount
        )
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        let currentDate = now()
        var validEntries: [String: PersistedEntry] = [:]
        for entry in decoded.entries {
            guard entry.identityHash.count == 64,
                  entry.identityHash.allSatisfy(\.isHexDigit),
                  entry.failureCount >= 1,
                  entry.failureCount <= 16,
                  validEntries[entry.identityHash] == nil else {
                throw ProviderRequestGatePersistenceError.blocked
            }
            guard entry.deadline > currentDate else { continue }
            validEntries[entry.identityHash] = entry
        }
        return LoadedPersistedState(
            entries: validEntries,
            needsRewrite: validEntries.count != decoded.entries.count
                || validEntries.isEmpty
                || validEntries.count > Self.maximumPersistedEntryCount
        )
    }

    private func persist(_ state: State, for key: String) {
        guard let deadline = state.cooldownUntil,
              let failureClass = state.failureClass,
              deadline > now(),
              state.failureCount >= 1,
              state.failureCount <= 16 else {
            clearPersistedEntry(for: key)
            return
        }
        pendingPersistedEntryClears.remove(key)
        persistedEntries[key] = PersistedEntry(
            identityHash: key,
            deadline: deadline,
            failureClass: failureClass,
            failureCount: state.failureCount
        )
        guard !deferPersistenceRewriteIfNeeded() else { return }
        do {
            try writePersistedState()
        } catch {
            blockPersistence(
                operation: .rewrite,
                identityHash: key,
                generation: state.generation
            )
        }
    }

    private func deferPersistenceRewriteIfNeeded() -> Bool {
        switch persistenceState {
        case .blocked(let retryAt, let failureCount, _):
            persistenceState = .blocked(
                retryAt: retryAt,
                failureCount: failureCount,
                operation: .rewrite
            )
            return true
        case .probing(let failureCount, _):
            persistenceState = .probing(
                failureCount: failureCount,
                operation: .rewrite
            )
            return true
        case .uninitialized, .available:
            return false
        }
    }

    private func clearPersistedEntry(for key: String) {
        pendingPersistedEntryClears.insert(key)
        let removedEntry = persistedEntries.removeValue(forKey: key) != nil
        guard isPersistenceAvailable else { return }
        guard removedEntry else {
            pendingPersistedEntryClears.remove(key)
            return
        }
        do {
            try writePersistedState()
        } catch {
            blockPersistence(
                operation: .rewrite,
                identityHash: key,
                generation: states[key]?.generation
            )
        }
    }

    private func writePersistedState() throws {
        guard let persistenceURL else {
            pendingPersistedEntryClears.removeAll()
            return
        }
        let currentDate = now()
        var entries = persistedEntries.values
            .filter {
                $0.deadline > currentDate &&
                    $0.identityHash.count == 64 &&
                    $0.identityHash.allSatisfy(\.isHexDigit) &&
                    $0.failureCount >= 1 &&
                    $0.failureCount <= 16
            }
            .sorted {
                if $0.deadline != $1.deadline { return $0.deadline > $1.deadline }
                return $0.identityHash < $1.identityHash
            }
        if entries.count > Self.maximumPersistedEntryCount {
            entries.removeLast(entries.count - Self.maximumPersistedEntryCount)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(PersistedState(entries: entries))
        while data.count > Self.maximumPersistenceByteCount, !entries.isEmpty {
            entries.removeLast()
            data = try encoder.encode(PersistedState(entries: entries))
        }
        persistedEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.identityHash, $0) })
        if entries.isEmpty {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: persistenceURL.path)
                guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                    throw ProviderRequestGatePersistenceError.blocked
                }
                try fileManager.removeItem(at: persistenceURL)
            } catch {
                guard Self.isExplicitMissingFileError(error) else { throw error }
            }
            pendingPersistedEntryClears.removeAll()
            return
        }
        guard data.count <= Self.maximumPersistenceByteCount else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let directory = persistenceURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(
            "." + persistenceURL.lastPathComponent + "." + UUID().uuidString + ".tmp"
        )
        do {
            if testProbe?.shouldFailWrite() == true {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: temporaryURL, options: .atomic)
            try setSecurePermissions(of: temporaryURL)
            let destinationExists: Bool
            do {
                let attributes = try fileManager.attributesOfItem(atPath: persistenceURL.path)
                guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                    throw ProviderRequestGatePersistenceError.blocked
                }
                destinationExists = true
            } catch {
                guard Self.isExplicitMissingFileError(error) else { throw error }
                destinationExists = false
            }
            if destinationExists {
                _ = try fileManager.replaceItemAt(persistenceURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: persistenceURL)
            }
            try setSecurePermissions(of: persistenceURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
        pendingPersistedEntryClears.removeAll()
    }

    private func setSecurePermissions(of url: URL) throws {
        if testProbe?.shouldFailPermissionChange() == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func blockPersistence(
        operation: PersistenceRecoveryOperation,
        previousFailureCount: Int? = nil,
        identityHash: String? = nil,
        generation: UInt64? = nil
    ) {
        guard persistenceURL != nil else { return }
        let currentFailureCount: Int
        if let previousFailureCount {
            currentFailureCount = previousFailureCount
        } else {
            switch persistenceState {
            case .blocked(_, let failureCount, _),
                 .probing(let failureCount, _):
                currentFailureCount = failureCount
            case .uninitialized, .available:
                currentFailureCount = 0
            }
        }
        let failureCount = min(16, currentFailureCount + 1)
        let delay = Self.persistenceRecoveryDelay(failureCount: failureCount)
        let retryAt = now().addingTimeInterval(delay)
        persistenceState = .blocked(
            retryAt: retryAt,
            failureCount: failureCount,
            operation: operation
        )
        testProbe?.recordPersistenceBlock()
        emitPersistenceDiagnostic(
            stage: "provider_gate_persistence_blocked",
            operation: operation,
            failureCount: failureCount,
            retryAt: retryAt,
            identityHash: identityHash,
            generation: generation
        )
        resumeAllAvailabilityWaiters()
    }

    private static func persistenceRecoveryDelay(failureCount: Int) -> TimeInterval {
        let exponent = min(4, max(0, failureCount - 1))
        return min(
            persistenceRecoveryMaximumDelay,
            persistenceRecoveryInitialDelay * pow(2, Double(exponent))
        )
    }

    private func emitPersistenceDiagnostic(
        stage: String,
        operation: PersistenceRecoveryOperation,
        failureCount: Int,
        retryAt: Date?,
        identityHash: String?,
        generation: UInt64?
    ) {
        let fingerprint = identityHash.map { String($0.prefix(12)) } ?? "-"
        let retrySeconds = retryAt.map { max(0, Int(ceil($0.timeIntervalSince(now())))) } ?? 0
        Self.logger.notice(
            "stage=\(stage, privacy: .public) providerGeneration=\(generation ?? 0, privacy: .public) providerFingerprint=\(fingerprint, privacy: .public) reason=\(operation.rawValue, privacy: .public) failureCount=\(failureCount, privacy: .public) cooldownRemainingSeconds=\(retrySeconds, privacy: .public)"
        )
    }

    private func resumeAllAvailabilityWaiters() {
        let keys = Array(availabilityWaiters.keys)
        keys.forEach { resumeAvailabilityWaiters(for: $0) }
    }

    private static func isExplicitMissingFileError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []
        while let error = current {
            guard visited.insert(ObjectIdentifier(error)).inserted else { return false }
            if error.domain == NSCocoaErrorDomain {
                if error.code == NSFileNoSuchFileError ||
                    error.code == NSFileReadNoSuchFileError {
                    return true
                }
            } else if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) {
                return true
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    private func boundedData(at url: URL, limit: Int) throws -> Data {
        if testProbe?.shouldFailRead() == true {
            throw CocoaError(.fileReadUnknown)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(64 * 1_024, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    private static func nanoseconds(until deadline: Date, now: Date) -> UInt64 {
        let interval = max(0, deadline.timeIntervalSince(now))
        return UInt64(min(interval, 15 * 60) * 1_000_000_000)
    }

    private func registerAvailabilityWaiter(
        _ continuation: CheckedContinuation<Void, Never>,
        for key: String,
        id: UUID,
        generation: UInt64
    ) {
        if Task.isCancelled {
            continuation.resume()
            return
        }
        let state = state(for: key)
        if generation < state.generation ||
            (!state.inFlight && (state.cooldownUntil == nil || state.cooldownUntil ?? .distantPast <= now())) {
            continuation.resume()
            return
        }
        let deadlineTask: Task<Void, Never>?
        if let deadline = state.cooldownUntil, deadline > now() {
            let delay = Self.nanoseconds(until: deadline, now: now())
            deadlineTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.resumeAvailabilityWaiter(for: key, id: id)
            }
        } else {
            deadlineTask = nil
        }
        availabilityWaiters[key, default: [:]][id] = AvailabilityWaiter(
            continuation: continuation,
            deadlineTask: deadlineTask
        )
    }

    private func resumeAvailabilityWaiters(for key: String) {
        guard let waiterMap = availabilityWaiters.removeValue(forKey: key) else { return }
        waiterMap.values.forEach {
            $0.deadlineTask?.cancel()
            $0.continuation.resume()
        }
    }

    private func resumeAvailabilityWaiter(for key: String, id: UUID) {
        guard let waiter = availabilityWaiters[key]?.removeValue(forKey: id) else { return }
        if availabilityWaiters[key]?.isEmpty == true { availabilityWaiters[key] = nil }
        waiter.deadlineTask?.cancel()
        waiter.continuation.resume()
    }

    private func cancelAvailabilityWaiter(for key: String, id: UUID) {
        guard let waiter = availabilityWaiters[key]?.removeValue(forKey: id) else { return }
        if availabilityWaiters[key]?.isEmpty == true { availabilityWaiters[key] = nil }
        waiter.deadlineTask?.cancel()
        waiter.continuation.resume()
    }
}
