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
    public static let shared = ProviderRequestGate()

    private struct State {
        var generation: UInt64 = 0
        var inFlight = false
        var failureCount = 0
        var cooldownUntil: Date?
        var failureClass: ProviderRequestFailureClass?
    }

    private var states: [String: State] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public static func identityHash(_ identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func invalidate(providerIdentity: String, generation: UInt64) {
        let key = Self.identityHash(providerIdentity)
        var state = states[key, default: State()]
        guard generation >= state.generation else { return }
        state.generation = generation &+ 1
        state.cooldownUntil = nil
        state.failureClass = nil
        state.failureCount = 0
        states[key] = state
    }

    public func cooldownDeadline(providerIdentity: String, generation: UInt64) -> Date? {
        let key = Self.identityHash(providerIdentity)
        guard let state = states[key], state.generation <= generation else { return nil }
        guard let deadline = state.cooldownUntil, deadline > now() else { return nil }
        return deadline
    }

    public func execute<T: Sendable>(
        providerIdentity: String,
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let key = Self.identityHash(providerIdentity)
        var state = states[key, default: State()]
        if generation < state.generation { throw ProviderRequestGateError.staleGeneration }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
            state.cooldownUntil = nil
            state.failureClass = nil
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
            return value
        } catch {
            var failed = states[key, default: State()]
            failed.inFlight = false
            if failed.generation != generation || Self.isCancellation(error) || Self.isStale(error) {
                states[key] = failed
                throw failed.generation == generation ? error : ProviderRequestGateError.staleGeneration
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
        let key = Self.identityHash(providerIdentity)
        var state = states[key, default: State()]
        guard state.generation <= generation,
              !Self.isCancellation(failure),
              !Self.isStale(failure) else { return }
        if generation > state.generation {
            state.generation = generation
            state.failureCount = 0
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
}
