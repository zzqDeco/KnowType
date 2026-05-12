import Foundation

public enum InputCommitDirective: Sendable, Equatable {
    case insertAndReset(String)
    case keepComposition
    case noAction
}

public enum InputCommitResultPolicy {
    public static func directive(for result: InputCommitResult) -> InputCommitDirective {
        switch result {
        case .commit(let text):
            return .insertAndReset(text)
        case .polishRequested:
            return .keepComposition
        case .noAction:
            return .noAction
        }
    }
}
