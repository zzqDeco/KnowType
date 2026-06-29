import Foundation

enum InputTaskKind: Hashable, Sendable {
    case localCandidates
    case panelRender
    case runtimeLexiconReload
}

struct InputGeneration: Sendable, Equatable {
    var compositionID: Int
    var rawRevision: Int
    var candidateRevision: Int
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
    private let budgetMilliseconds: Double

    init(
        enabled: Bool = ProcessInfo.processInfo.environment["KNOWTYPE_INPUT_LATENCY_DEBUG"] == "1",
        budgetMilliseconds: Double = Double(ProcessInfo.processInfo.environment["KNOWTYPE_INPUT_LATENCY_BUDGET_MS"] ?? "") ?? 8
    ) {
        self.enabled = enabled
        self.budgetMilliseconds = budgetMilliseconds
    }

    func trace<T>(_ name: String, operation: () -> T) -> T {
        guard enabled else {
            return operation()
        }
        let start = ContinuousClock.now
        let value = operation()
        let elapsed = start.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        if milliseconds >= budgetMilliseconds {
            fputs(
                "KnowType input latency: stage=\(name) ms=\(String(format: "%.2f", milliseconds)) budget=\(String(format: "%.2f", budgetMilliseconds))\n",
                stderr
            )
        }
        return value
    }
}
