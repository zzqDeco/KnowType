import Foundation

public enum InputCommitDirective: Sendable, Equatable {
    case insertAndReset(String)
    case requestPolishAndKeepComposition(String)
    case keepComposition
    case noAction
}

public enum InputCommitResultPolicy {
    public static func directive(for result: InputCommitResult) -> InputCommitDirective {
        switch result {
        case .commit(let text):
            return .insertAndReset(text)
        case .polishRequested(let text):
            return .requestPolishAndKeepComposition(text)
        case .noAction:
            return .noAction
        }
    }

    public static func shouldConsumeNoAction(hasComposition: Bool) -> Bool {
        hasComposition
    }
}
