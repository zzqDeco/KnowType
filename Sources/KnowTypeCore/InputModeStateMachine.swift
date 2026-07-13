import Foundation

public enum InputPunctuationSource: String, Sendable, Equatable {
    case linked
    case manual
}

public enum InputModeTransitionEvent: Sendable, Equatable {
    case toggleTextMode
    case togglePunctuationMode
    case toggleSymbolWidth
    case setSymbolWidth(InputSymbolWidth)
}

public struct InputModeSnapshot: Sendable, Equatable {
    public var state: InputModeState
    public var punctuationSource: InputPunctuationSource
    public var generation: Int

    public init(
        state: InputModeState,
        punctuationSource: InputPunctuationSource,
        generation: Int
    ) {
        self.state = state
        self.punctuationSource = punctuationSource
        self.generation = generation
    }
}

public struct InputModeTransition: Sendable, Equatable {
    public var previous: InputModeSnapshot
    public var current: InputModeSnapshot

    public init(previous: InputModeSnapshot, current: InputModeSnapshot) {
        self.previous = previous
        self.current = current
    }

    public var didChange: Bool {
        previous != current
    }
}

public struct InputModeStateMachine: Sendable, Equatable {
    public private(set) var snapshot: InputModeSnapshot

    public init(symbolWidth: InputSymbolWidth = .halfWidth) {
        self.snapshot = InputModeSnapshot(
            state: InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: symbolWidth
            ),
            punctuationSource: .linked,
            generation: 0
        )
    }

    @discardableResult
    public mutating func transition(_ event: InputModeTransitionEvent) -> InputModeTransition {
        let previous = snapshot
        var nextState = previous.state
        var nextPunctuationSource = previous.punctuationSource

        switch event {
        case .toggleTextMode:
            nextState.textMode.toggle()
            nextState.punctuationMode = nextState.textMode == .chinese ? .chinese : .english
            nextPunctuationSource = .linked
        case .togglePunctuationMode:
            guard nextState.textMode == .chinese else {
                return InputModeTransition(previous: previous, current: previous)
            }
            nextState.punctuationMode.toggle()
            nextPunctuationSource = .manual
        case .toggleSymbolWidth:
            nextState.symbolWidth.toggle()
        case .setSymbolWidth(let width):
            nextState.symbolWidth = width
        }

        guard nextState != previous.state || nextPunctuationSource != previous.punctuationSource else {
            return InputModeTransition(previous: previous, current: previous)
        }
        snapshot = InputModeSnapshot(
            state: nextState,
            punctuationSource: nextPunctuationSource,
            generation: previous.generation + 1
        )
        return InputModeTransition(previous: previous, current: snapshot)
    }
}
