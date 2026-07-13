import Foundation
import KnowTypeCore

protocol InputModeStateRuntime: AnyObject, Sendable {
    func currentSnapshot() -> InputModeSnapshot

    @discardableResult
    func transition(_ event: InputModeTransitionEvent) -> InputModeTransition

    @discardableResult
    func synchronizeConfiguredSymbolWidth(_ width: InputSymbolWidth) -> InputModeTransition
}

final class ProcessInputModeStateRuntime: InputModeStateRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var stateMachine: InputModeStateMachine
    private var configuredSymbolWidth: InputSymbolWidth

    init(initialSymbolWidth: InputSymbolWidth = .halfWidth) {
        self.stateMachine = InputModeStateMachine(symbolWidth: initialSymbolWidth)
        self.configuredSymbolWidth = initialSymbolWidth
    }

    func currentSnapshot() -> InputModeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return stateMachine.snapshot
    }

    @discardableResult
    func transition(_ event: InputModeTransitionEvent) -> InputModeTransition {
        lock.lock()
        defer { lock.unlock() }
        return stateMachine.transition(event)
    }

    @discardableResult
    func synchronizeConfiguredSymbolWidth(_ width: InputSymbolWidth) -> InputModeTransition {
        lock.lock()
        defer { lock.unlock() }
        let current = stateMachine.snapshot
        guard width != configuredSymbolWidth else {
            return InputModeTransition(previous: current, current: current)
        }
        configuredSymbolWidth = width
        return stateMachine.transition(.setSymbolWidth(width))
    }
}
