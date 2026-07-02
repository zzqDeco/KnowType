import Foundation
import KnowTypeCore

enum InputTaskKind: Hashable, Sendable {
    case panelRender
    case runtimeLexiconReload
}

final class InputTaskSupervisor: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [InputTaskKind: Task<Void, Never>] = [:]
    private var cancellationCounts: [InputTaskKind: Int] = [:]

    func replace(_ kind: InputTaskKind, with task: Task<Void, Never>?) {
        lock.lock()
        let previous = tasks[kind]
        if let task {
            tasks[kind] = task
        } else {
            tasks[kind] = nil
        }
        if previous != nil {
            cancellationCounts[kind, default: 0] += 1
        }
        lock.unlock()
        previous?.cancel()
    }

    func cancel(_ kind: InputTaskKind) {
        replace(kind, with: nil)
    }

    func cancelAll() {
        lock.lock()
        let activeTasks = Array(tasks.values)
        for kind in tasks.keys {
            cancellationCounts[kind, default: 0] += 1
        }
        tasks.removeAll()
        lock.unlock()
        activeTasks.forEach { $0.cancel() }
    }

    func cancellationCount(for kind: InputTaskKind) -> Int {
        lock.lock()
        let count = cancellationCounts[kind, default: 0]
        lock.unlock()
        return count
    }
}

struct InputLatencyTracer: Sendable {
    private let enabled: Bool
    private let perfDebugEnabled: Bool
    private let budgetMilliseconds: Double

    init(
        enabled: Bool = ProcessInfo.processInfo.environment["KNOWTYPE_INPUT_LATENCY_DEBUG"] == "1",
        perfDebugEnabled: Bool = ProcessInfo.processInfo.environment[InputDebugDiagnostics.performanceEnvironmentKey] == "1",
        budgetMilliseconds: Double = Double(ProcessInfo.processInfo.environment["KNOWTYPE_INPUT_LATENCY_BUDGET_MS"] ?? "") ?? 8
    ) {
        self.enabled = enabled
        self.perfDebugEnabled = perfDebugEnabled
        self.budgetMilliseconds = budgetMilliseconds
    }

    var isEnabled: Bool {
        enabled || perfDebugEnabled
    }

    func trace<T>(
        _ name: String,
        fields: [InputDebugDiagnostics.Field] = [],
        operation: () -> T
    ) -> T {
        guard isEnabled else {
            return operation()
        }
        return InputDebugDiagnostics.trace(
            category: .inputLatency,
            stage: name,
            budgetMilliseconds: budgetMilliseconds,
            fields: fields,
            operation: operation
        )
    }
}
