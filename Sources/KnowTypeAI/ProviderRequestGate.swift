import CryptoKit
import Foundation
import KnowTypeProviders

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
    case persistenceBlocked
}

final class ProviderRequestGateTestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failedPermissionChangesRemaining = 0
    private var failedReadsRemaining = 0
    private var failedWritesRemaining = 0
    private var admittedAttempts = 0
    private var preflightChecks = 0

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

public actor ProviderRequestGate {
    public static let shared = ProviderRequestGate(persistenceURL: defaultPersistenceURL())

    private static let maximumPersistenceByteCount = 64 * 1_024
    private static let maximumPersistedEntryCount = 256

    private struct State {
        var generation: UInt64 = 0
        var activeAttemptID: UUID?
        var timedOutAttemptID: UUID?
        var failureCount = 0
        var cooldownUntil: Date?
        var failureClass: ProviderRequestFailureClass?

        var inFlight: Bool { activeAttemptID != nil }
    }

    private struct Attempt: Sendable {
        var id: UUID
        var identityHash: String
        var generation: UInt64
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

    private struct AvailabilityWaiter {
        var continuation: CheckedContinuation<Void, Never>
        var deadlineTask: Task<Void, Never>?
    }

    private var states: [String: State] = [:]
    private let now: @Sendable () -> Date
    private let persistenceURL: URL?
    private let fileManager: FileManager
    private let testProbe: ProviderRequestGateTestProbe?
    private var persistedEntries: [String: PersistedEntry] = [:]
    private var persistenceLoaded = false
    private var persistenceBlocked = false
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
    }

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        persistenceURL: URL? = nil,
        fileManager: FileManager = .default,
        testProbe: ProviderRequestGateTestProbe
    ) {
        self.now = now
        self.persistenceURL = persistenceURL
        self.fileManager = fileManager
        self.testProbe = testProbe
    }

    public static func identityHash(_ identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func invalidate(providerIdentity: String, generation: UInt64) {
        loadPersistedStateIfNeeded()
        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        guard generation >= state.generation else { return }
        state.generation = generation &+ 1
        state.cooldownUntil = nil
        state.failureClass = nil
        state.failureCount = 0
        state.timedOutAttemptID = nil
        states[key] = state
        if !persistenceBlocked {
            clearPersistedEntry(for: key)
        }
        resumeAvailabilityWaiters(for: key)
    }

    public func cooldownDeadline(providerIdentity: String, generation: UInt64) -> Date? {
        loadPersistedStateIfNeeded()
        guard !persistenceBlocked else { return nil }
        let key = Self.identityHash(providerIdentity)
        let state = state(for: key)
        guard !persistenceBlocked else { return nil }
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
        loadPersistedStateIfNeeded()
        guard !persistenceBlocked else { return .persistenceBlocked }

        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        guard !persistenceBlocked else { return .persistenceBlocked }
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
            guard !persistenceBlocked else { return .persistenceBlocked }
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
        loadPersistedStateIfNeeded()
        return persistenceBlocked ? .persistenceBlocked : .available
    }

    public func waitForAvailability(providerIdentity: String, generation: UInt64) async {
        let key = Self.identityHash(providerIdentity)
        while !Task.isCancelled {
            loadPersistedStateIfNeeded()
            guard !persistenceBlocked else { return }
            let state = state(for: key)
            guard !persistenceBlocked else { return }
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
        let attempt = try beginAttempt(
            providerIdentity: providerIdentity,
            generation: generation
        )
        return try await perform(attempt: attempt, operation: operation)
    }

    func executeWithHardTimeout<T: Sendable>(
        providerIdentity: String,
        generation: UInt64,
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let attempt = try beginAttempt(
            providerIdentity: providerIdentity,
            generation: generation
        )
        return try await withTimeout(
            nanoseconds: timeoutNanoseconds,
            onTimeout: { claimTimeout in
                try await self.recordTimeout(
                    for: attempt,
                    claimingTimeout: claimTimeout
                )
            }
        ) {
            try await self.perform(attempt: attempt, operation: operation)
        }
    }

    private func beginAttempt(
        providerIdentity: String,
        generation: UInt64
    ) throws -> Attempt {
        loadPersistedStateIfNeeded()
        guard !persistenceBlocked else {
            throw ProviderRequestGatePersistenceError.blocked
        }
        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        guard !persistenceBlocked else {
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
            guard !persistenceBlocked else {
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
        let attempt = Attempt(id: UUID(), identityHash: key, generation: generation)
        state.activeAttemptID = attempt.id
        state.timedOutAttemptID = nil
        states[key] = state
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

    private func recordTimeout(
        for attempt: Attempt,
        claimingTimeout: @Sendable () -> Bool
    ) throws -> Bool {
        var state = states[attempt.identityHash, default: State()]
        guard state.generation == attempt.generation else {
            throw ProviderRequestGateError.staleGeneration
        }
        guard state.activeAttemptID == attempt.id else { return false }
        guard state.timedOutAttemptID != attempt.id,
              claimingTimeout() else { return false }

        state.failureCount = min(16, state.failureCount + 1)
        state.failureClass = .timeout
        state.cooldownUntil = now().addingTimeInterval(
            Self.cooldownSeconds(
                failureClass: .timeout,
                failureCount: state.failureCount,
                retryAfter: nil
            )
        )
        state.timedOutAttemptID = attempt.id
        states[attempt.identityHash] = state
        persist(state, for: attempt.identityHash)
        return true
    }

    private func finishSuccess<T: Sendable>(_ value: T, attempt: Attempt) throws -> T {
        var state = states[attempt.identityHash, default: State()]
        guard state.activeAttemptID == attempt.id else {
            throw ProviderRequestGateError.staleGeneration
        }
        state.activeAttemptID = nil
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
        loadPersistedStateIfNeeded()
        guard !persistenceBlocked else { return }
        if failure is ProviderRequestBudgetError { return }
        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        guard !persistenceBlocked else { return }
        guard state.generation <= generation,
              !Self.isCancellation(failure),
              !Self.isStale(failure) else { return }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            clearPersistedEntry(for: key)
            guard !persistenceBlocked else { return }
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

    private func loadPersistedStateIfNeeded() {
        guard !persistenceLoaded else { return }
        persistenceLoaded = true
        guard let persistenceURL else { return }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: persistenceURL.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                blockPersistence()
                return
            }
        } catch {
            if Self.isExplicitMissingFileError(error) { return }
            blockPersistence()
            return
        }
        do {
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
            persistedEntries = validEntries
            if validEntries.count != decoded.entries.count || validEntries.isEmpty {
                try writePersistedState()
            }
        } catch {
            blockPersistence()
        }
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
        persistedEntries[key] = PersistedEntry(
            identityHash: key,
            deadline: deadline,
            failureClass: failureClass,
            failureCount: state.failureCount
        )
        do {
            try writePersistedState()
        } catch {
            blockPersistence()
        }
    }

    private func clearPersistedEntry(for key: String) {
        guard persistedEntries.removeValue(forKey: key) != nil else { return }
        do {
            try writePersistedState()
        } catch {
            blockPersistence()
        }
    }

    private func writePersistedState() throws {
        guard let persistenceURL else { return }
        guard !persistenceBlocked else {
            throw ProviderRequestGatePersistenceError.blocked
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
                try fileManager.removeItem(at: persistenceURL)
            } catch {
                guard Self.isExplicitMissingFileError(error) else { throw error }
            }
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
                _ = try fileManager.replaceItem(at: persistenceURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: persistenceURL)
            }
            try setSecurePermissions(of: persistenceURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func setSecurePermissions(of url: URL) throws {
        if testProbe?.shouldFailPermissionChange() == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func blockPersistence() {
        guard persistenceURL != nil else { return }
        persistenceBlocked = true
        let keys = Array(availabilityWaiters.keys)
        keys.forEach { resumeAvailabilityWaiters(for: $0) }
    }

    private static func isExplicitMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
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
