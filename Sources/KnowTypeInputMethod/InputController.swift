import Foundation
import KnowTypeCore

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, @unchecked Sendable {
    private let sessionController = InputSessionController()
    private let keyMapper = InputKeyCommandMapper()
    private let candidateListBuilder = InputCandidateListBuilder()
    private var rawBuffer = ""
    private var lastSuggestion: SuggestionResponse?
    private var lastSuggestionRawInput: String?
    private var locale: KnowTypeLocale = .mixed
    private var suggestionTask: Task<Void, Never>?

    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: keyCode,
            modifiers: modifierSet(from: flags)
        )

        switch keyMapper.intent(for: stroke) {
        case .append(let text):
            rawBuffer.append(text)
            invalidateSuggestion()
            updateComposition()
            refreshSuggestion(client: sender)
            return true
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                return false
            }
            rawBuffer.removeLast()
            invalidateSuggestion()
            refreshSuggestion(client: sender)
            updateComposition()
            return true
        case .action(let action):
            return commit(action: action, client: sender)
        case .ignored:
            return false
        }
    }

    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        rawBuffer.append(string ?? "")
        invalidateSuggestion()
        updateComposition()
        refreshSuggestion(client: sender)
        return true
    }

    public override func composedString(_ sender: Any!) -> Any! {
        guard let prefix = lastSuggestion?.prefixCandidates.first?.text else {
            return rawBuffer
        }
        return prefix
    }

    public override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: rawBuffer)
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        candidateListBuilder.candidates(rawInput: rawBuffer, suggestion: lastSuggestion)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(action: .space, client: sender)
    }

    private func refreshSuggestion(client sender: Any!) {
        suggestionTask?.cancel()
        let rawInput = rawBuffer
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawInput) else {
            return
        }
        let appBundleID = appBundleIdentifier(client: sender)
        suggestionTask = Task { [weak self] in
            guard let self else {
                return
            }
            let suggestion = await self.sessionController.update(
                rawInput: rawInput,
                appBundleID: appBundleID,
                locale: self.locale
            )
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard SuggestionPublicationGuard.shouldPublish(
                    requestedRawInput: rawInput,
                    currentRawInput: self.rawBuffer,
                    isCancelled: Task.isCancelled
                ) else {
                    return
                }
                self.lastSuggestion = suggestion
                self.lastSuggestionRawInput = rawInput
                self.updateComposition()
            }
        }
    }

    private func appBundleIdentifier(client sender: Any!) -> String? {
        (sender as? IMKTextInput)?.bundleIdentifier()
    }

    @discardableResult
    private func commit(action: InputAction, client sender: Any!) -> Bool {
        let result = commitResult(for: action)
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
            insert(text, client: sender)
            resetComposition()
            return true
        case .requestPolishAndKeepComposition(let text):
            Task { [sessionController] in
                await sessionController.requestPolish(rawInput: text)
            }
            updateComposition()
            return true
        case .keepComposition:
            updateComposition()
            return true
        case .noAction:
            return InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: !rawBuffer.isEmpty)
        }
    }

    private func commitResult(for action: InputAction) -> InputCommitResult {
        guard let suggestion = lastSuggestion,
              SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: lastSuggestionRawInput,
                currentRawInput: rawBuffer
              ) else {
            guard !rawBuffer.isEmpty else {
                return .noAction
            }
            switch action {
            case .space, .tab:
                return .commit(rawBuffer)
            case .optionR:
                return .polishRequested(rawBuffer)
            case .optionNumber:
                return .noAction
            }
        }
        return InputCompositionController().handle(
            action: action,
            prefixCandidates: suggestion.prefixCandidates,
            continuationCandidates: suggestion.continuationCandidates,
            originalText: rawBuffer
        )
    }

    private func insert(_ text: String, client sender: Any!) {
        let replacement = NSRange(location: NSNotFound, length: NSNotFound)
        if let client = sender as? IMKTextInput {
            client.insertText(text, replacementRange: replacement)
        }
    }

    private func resetComposition() {
        rawBuffer = ""
        invalidateSuggestion()
        updateComposition()
    }

    private func invalidateSuggestion() {
        lastSuggestion = nil
        lastSuggestionRawInput = nil
        suggestionTask?.cancel()
        suggestionTask = nil
    }

    private func modifierSet(from flags: Int) -> Set<InputModifier> {
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(flags))
        var modifiers: Set<InputModifier> = []
        if eventFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if eventFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if eventFlags.contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }
}
#endif
