import Foundation
import KnowTypeProviders

public actor AIHealthMonitor {
    private let failureThreshold: Int
    private let cooldownSeconds: TimeInterval
    private var consecutiveFailures = 0
    private var cooldownUntil: Date?

    public init(failureThreshold: Int = 3, cooldownSeconds: TimeInterval = 60) {
        self.failureThreshold = max(1, failureThreshold)
        self.cooldownSeconds = max(1, cooldownSeconds)
    }

    public func unavailableReason(now: Date = Date()) -> String? {
        guard let cooldownUntil else {
            return nil
        }
        if now < cooldownUntil {
            return "AI 暂不可用"
        }
        self.cooldownUntil = nil
        consecutiveFailures = 0
        return nil
    }

    public func recordSuccess() {
        consecutiveFailures = 0
        cooldownUntil = nil
    }

    public func recordFailure(_ error: Error, now: Date = Date()) {
        guard Self.countsTowardCooldown(error) else {
            return
        }
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold {
            cooldownUntil = now.addingTimeInterval(cooldownSeconds)
        }
    }

    private static func countsTowardCooldown(_ error: Error) -> Bool {
        if error is TimeoutError {
            return true
        }
        if case ProviderError.httpStatus(let status, _) = error,
           status == 429 || (500...599).contains(status) {
            return true
        }
        if case ProviderError.invalidResponse = error {
            return true
        }
        return false
    }
}

public struct TimeoutError: Error, Sendable, Equatable {}
