import Foundation
import KnowTypeCore

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, @unchecked Sendable {
    private let sessionController = InputSessionController()
    private let keyMapper = InputKeyCommandMapper()
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
            commit(action: action, client: sender)
            return true
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
        guard let suggestion = lastSuggestion else {
            return rawBuffer.isEmpty ? [] : [rawBuffer]
        }
        return suggestion.prefixCandidates.map(\.text) + suggestion.continuationCandidates.map(\.text)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(action: .space, client: sender)
    }

    private func refreshSuggestion(client sender: Any!) {
        suggestionTask?.cancel()
        let rawInput = rawBuffer
        suggestionTask = Task { [weak self] in
            guard let self else {
                return
            }
            let suggestion = await self.sessionController.update(
                rawInput: rawInput,
                appBundleID: nil,
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

    private func commit(action: InputAction, client sender: Any!) {
        let result = commitResult(for: action)
        switch result {
        case .commit(let text), .polishRequested(let text):
            insert(text, client: sender)
            resetComposition()
        case .noAction:
            if !rawBuffer.isEmpty {
                insert(rawBuffer, client: sender)
                resetComposition()
            }
        }
    }

    private func commitResult(for action: InputAction) -> InputCommitResult {
        guard let suggestion = lastSuggestion,
              SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: lastSuggestionRawInput,
                currentRawInput: rawBuffer
              ) else {
            return rawBuffer.isEmpty ? .noAction : .commit(rawBuffer)
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
