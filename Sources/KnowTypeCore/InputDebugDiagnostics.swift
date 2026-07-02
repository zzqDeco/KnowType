import Foundation
import OSLog

public enum InputDebugDiagnostics {
    public enum Category: String, Sendable {
        case ai
        case anchor
        case clientWrite = "client_write"
        case inputLatency = "input_latency"
        case panel
        case performance
        case rime
        case startup
        case turn

        var environmentKey: String? {
            switch self {
            case .ai:
                return "KNOWTYPE_AI_DEBUG"
            case .anchor:
                return "KNOWTYPE_ANCHOR_DEBUG"
            case .clientWrite:
                return "KNOWTYPE_CLIENT_WRITE_DEBUG"
            case .inputLatency:
                return "KNOWTYPE_INPUT_LATENCY_DEBUG"
            case .panel:
                return "KNOWTYPE_PANEL_DEBUG"
            case .performance,
                 .rime:
                return nil
            case .startup:
                return "KNOWTYPE_STARTUP_DEBUG"
            case .turn:
                return "KNOWTYPE_TURN_DEBUG"
            }
        }
    }

    public enum FieldKey: String, Sendable, CaseIterable {
        case anchorSource
        case budgetMs
        case bundleID
        case elapsedMs
        case handled
        case panelGeneration
        case prefixLength
        case provider
        case rawLength
        case rawRevision
        case reason
        case requestID
        case stage
        case turnID
        case compositionID
        case writeMode
    }

    public struct Field: Sendable, Equatable {
        public var key: FieldKey
        public var value: String

        public init(_ key: FieldKey, _ value: String) {
            self.key = key
            self.value = value
        }

        public init(_ key: FieldKey, _ value: CustomStringConvertible) {
            self.init(key, value.description)
        }
    }

    public typealias Environment = [String: String]
    public typealias StderrSink = @Sendable (String) -> Void

    public static let performanceEnvironmentKey = "KNOWTYPE_PERF_DEBUG"
    public static let latencyBudgetEnvironmentKey = "KNOWTYPE_INPUT_LATENCY_BUDGET_MS"
    public static let defaultLatencyBudgetMilliseconds = 8.0

    public static func isEnabled(
        _ category: Category,
        environment: Environment = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment[performanceEnvironmentKey] == "1" {
            return true
        }
        guard let environmentKey = category.environmentKey else {
            return false
        }
        return environment[environmentKey] == "1"
    }

    public static func latencyBudgetMilliseconds(
        environment: Environment = ProcessInfo.processInfo.environment
    ) -> Double {
        Double(environment[latencyBudgetEnvironmentKey] ?? "") ?? defaultLatencyBudgetMilliseconds
    }

    public static func shouldEmitLatency(
        elapsedMilliseconds: Double,
        budgetMilliseconds: Double,
        environment: Environment = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment[performanceEnvironmentKey] == "1" {
            return true
        }
        return environment["KNOWTYPE_INPUT_LATENCY_DEBUG"] == "1"
            && elapsedMilliseconds >= budgetMilliseconds
    }

    @discardableResult
    public static func emit(
        category: Category,
        fields: [Field],
        environment: Environment = ProcessInfo.processInfo.environment,
        stderrSink: StderrSink = defaultStderrSink,
        logger: Logger? = nil,
        force: Bool = false
    ) -> Bool {
        guard force || isEnabled(category, environment: environment) else {
            return false
        }
        let line = formatLine(category: category, fields: fields)
        stderrSink(line)
        (logger ?? Logger(subsystem: "com.knowtype.inputmethod.KnowType", category: category.rawValue))
            .notice("\(line.trimmingCharacters(in: .newlines), privacy: .public)")
        return true
    }

    public static func formatLine(category: Category, fields: [Field]) -> String {
        var components = [
            "KnowType debug:",
            "category=\(category.rawValue)"
        ]
        for field in fields {
            components.append("\(field.key.rawValue)=\(sanitizeValue(field.value))")
        }
        return components.joined(separator: " ") + "\n"
    }

    public static func trace<T>(
        category: Category,
        stage: String,
        budgetMilliseconds: Double? = nil,
        fields: [Field] = [],
        environment: Environment = ProcessInfo.processInfo.environment,
        stderrSink: StderrSink = defaultStderrSink,
        operation: () -> T
    ) -> T {
        let shouldTrace = isEnabled(category, environment: environment)
            || category == .inputLatency
            || category == .performance
        guard shouldTrace else {
            return operation()
        }
        let start = ContinuousClock.now
        let value = operation()
        let elapsed = milliseconds(start.duration(to: .now))
        let budget = budgetMilliseconds ?? latencyBudgetMilliseconds(environment: environment)
        if category == .inputLatency,
           !shouldEmitLatency(
               elapsedMilliseconds: elapsed,
               budgetMilliseconds: budget,
               environment: environment
           ) {
            return value
        }
        var outputFields = [
            Field(.stage, stage),
            Field(.elapsedMs, String(format: "%.2f", elapsed))
        ]
        if category == .inputLatency {
            outputFields.append(Field(.budgetMs, String(format: "%.2f", budget)))
        }
        outputFields.append(contentsOf: fields)
        emit(
            category: category,
            fields: outputFields,
            environment: environment,
            stderrSink: stderrSink
        )
        return value
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func sanitizeValue(_ value: String) -> String {
        let trimmed = value.isEmpty ? "-" : value
        var result = ""
        result.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                result.append("_")
            } else if scalar.value >= 0x20, scalar.value != 0x7F {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        return result
    }

    public static let defaultStderrSink: StderrSink = { line in
        fputs(line, stderr)
    }
}
