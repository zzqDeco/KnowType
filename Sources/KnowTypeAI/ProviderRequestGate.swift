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

public actor ProviderRequestGate {
    public static let shared = ProviderRequestGate(persistenceURL: defaultPersistenceURL())

    private struct State {
        var generation: UInt64 = 0
        var inFlight = false
        var failureCount = 0
        var cooldownUntil: Date?
        var failureClass: ProviderRequestFailureClass?
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

    private var states: [String: State] = [:]
    private let now: @Sendable () -> Date
    private let persistenceURL: URL?
    private let fileManager: FileManager
    private var persistedEntries: [String: PersistedEntry] = [:]
    private var persistenceLoaded = false
    private var availabilityWaiters: [String: [UUID: CheckedContinuation<Void, Never>]] = [:]

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        persistenceURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.now = now
        self.persistenceURL = persistenceURL
        self.fileManager = fileManager
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
        states[key] = state
        clearPersistedEntry(for: key)
        resumeAvailabilityWaiters(for: key)
    }

    public func cooldownDeadline(providerIdentity: String, generation: UInt64) -> Date? {
        loadPersistedStateIfNeeded()
        let key = Self.identityHash(providerIdentity)
        let state = state(for: key)
        guard state.generation <= generation else { return nil }
        guard let deadline = state.cooldownUntil, deadline > now() else {
            if persistedEntries[key] != nil { clearPersistedEntry(for: key) }
            return nil
        }
        return deadline
    }

    public func waitForAvailability(providerIdentity: String, generation: UInt64) async {
        let key = Self.identityHash(providerIdentity)
        while !Task.isCancelled {
            loadPersistedStateIfNeeded()
            let state = state(for: key)
            if generation < state.generation {
                return
            }
            if !state.inFlight &&
                (state.cooldownUntil == nil || state.cooldownUntil ?? .distantPast <= now()) {
                if persistedEntries[key] != nil { clearPersistedEntry(for: key) }
                return
            }
            if let deadline = state.cooldownUntil, deadline > now() {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(until: deadline, now: now()))
                } catch {
                    return
                }
                continue
            }

            let waiterID = UUID()
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled {
                        continuation.resume()
                    } else {
                        availabilityWaiters[key, default: [:]][waiterID] = continuation
                    }
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
        loadPersistedStateIfNeeded()
        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        if states[key] == nil, persistedEntries[key] != nil {
            state.generation = generation
        }
        if generation < state.generation { throw ProviderRequestGateError.staleGeneration }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            state.cooldownUntil = nil
            state.failureClass = nil
            clearPersistedEntry(for: key)
        }
        if state.inFlight { throw ProviderRequestGateError.busy }
        if let deadline = state.cooldownUntil, deadline > now() {
            throw ProviderRequestGateError.cooldown(
                deadline: deadline,
                failureClass: state.failureClass ?? .transport
            )
        }
        state.inFlight = true
        states[key] = state

        do {
            let value = try await operation()
            var completed = states[key, default: State()]
            completed.inFlight = false
            guard completed.generation == generation else {
                states[key] = completed
                throw ProviderRequestGateError.staleGeneration
            }
            completed.failureCount = 0
            completed.cooldownUntil = nil
            completed.failureClass = nil
            states[key] = completed
            clearPersistedEntry(for: key)
            resumeAvailabilityWaiters(for: key)
            return value
        } catch {
            var failed = states[key, default: State()]
            failed.inFlight = false
            if failed.generation != generation || Self.isCancellation(error) || Self.isStale(error) {
                states[key] = failed
                resumeAvailabilityWaiters(for: key)
                throw failed.generation == generation ? error : ProviderRequestGateError.staleGeneration
            }
            if error is ProviderRequestBudgetError {
                states[key] = failed
                resumeAvailabilityWaiters(for: key)
                throw error
            }
            let failureClass = Self.classify(error)
            failed.failureCount += 1
            failed.failureClass = failureClass
            failed.cooldownUntil = now().addingTimeInterval(
                Self.cooldownSeconds(
                    failureClass: failureClass,
                    failureCount: failed.failureCount,
                    retryAfter: (error as? ProviderRateLimitError)?.retryAfterSeconds
                )
            )
            states[key] = failed
            persist(failed, for: key)
            resumeAvailabilityWaiters(for: key)
            throw error
        }
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
        if failure is ProviderRequestBudgetError { return }
        let key = Self.identityHash(providerIdentity)
        var state = state(for: key)
        guard state.generation <= generation,
              !Self.isCancellation(failure),
              !Self.isStale(failure) else { return }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            clearPersistedEntry(for: key)
        }
        let failureClass = forcedClass ?? Self.classify(failure)
        state.failureCount += 1
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
        guard let persistenceURL,
              fileManager.fileExists(atPath: persistenceURL.path) else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
        guard let data = try? boundedData(at: persistenceURL, limit: 64 * 1_024),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        let currentDate = now()
        var validEntries: [String: PersistedEntry] = [:]
        for entry in decoded.entries {
            guard entry.identityHash.count == 64,
                  entry.identityHash.allSatisfy(\.isHexDigit),
                  entry.deadline > currentDate,
                  entry.failureCount >= 1,
                  entry.failureCount <= 16 else { continue }
            validEntries[entry.identityHash] = entry
        }
        persistedEntries = validEntries
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
        writePersistedState()
    }

    private func clearPersistedEntry(for key: String) {
        guard persistedEntries.removeValue(forKey: key) != nil else { return }
        writePersistedState()
    }

    private func writePersistedState() {
        guard let persistenceURL else { return }
        if persistedEntries.isEmpty {
            try? fileManager.removeItem(at: persistenceURL)
            return
        }
        let entries = persistedEntries.values.sorted { $0.identityHash < $1.identityHash }
        guard let data = try? JSONEncoder().encode(PersistedState(entries: entries)) else { return }
        let directory = persistenceURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryURL = directory.appendingPathComponent(
                "." + persistenceURL.lastPathComponent + "." + UUID().uuidString + ".tmp"
            )
            do {
                try data.write(to: temporaryURL, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
                if fileManager.fileExists(atPath: persistenceURL.path) {
                    _ = try fileManager.replaceItem(at: persistenceURL, withItemAt: temporaryURL)
                } else {
                    try fileManager.moveItem(at: temporaryURL, to: persistenceURL)
                }
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
            }
        } catch {
            return
        }
    }

    private func boundedData(at url: URL, limit: Int) throws -> Data {
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

    private func resumeAvailabilityWaiters(for key: String) {
        guard let waiterMap = availabilityWaiters.removeValue(forKey: key) else { return }
        waiterMap.values.forEach { $0.resume() }
    }

    private func cancelAvailabilityWaiter(for key: String, id: UUID) {
        guard let continuation = availabilityWaiters[key]?.removeValue(forKey: id) else { return }
        if availabilityWaiters[key]?.isEmpty == true { availabilityWaiters[key] = nil }
        continuation.resume()
    }
}
