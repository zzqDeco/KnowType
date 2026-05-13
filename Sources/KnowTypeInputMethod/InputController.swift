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
    private var nativeCandidates: IMKCandidates?
    private var displayedNativeCandidates: [InputCandidateSelection] = []
    private var selectedNativeCandidate: InputCandidateSelection?

    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: keyCode,
            modifiers: modifierSet(from: flags)
        )

        return handle(intent: keyMapper.intent(for: stroke), client: sender)
    }

    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: Self.textOnlyKeyCode
        )
        return handle(intent: keyMapper.intent(for: stroke), client: sender)
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
        let selections = candidateListBuilder.candidateSelections(rawInput: rawBuffer, suggestion: lastSuggestion)
        displayedNativeCandidates = selections
        return selections.map(\.text)
    }

    public override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        selectNativeCandidate(matching: candidateString?.string)
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        selectNativeCandidate(matching: candidateString?.string)
        commit(action: .space, client: client())
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event,
              event.type == .keyDown else {
            return false
        }
        let characters = event.modifierFlags.contains(.option)
            ? event.charactersIgnoringModifiers ?? event.characters ?? ""
            : event.characters ?? event.charactersIgnoringModifiers ?? ""
        let stroke = InputKeyStroke(
            text: characters,
            keyCode: Int(event.keyCode),
            modifiers: modifierSet(from: Int(event.modifierFlags.rawValue))
        )
        return handle(intent: keyMapper.intent(for: stroke), client: sender)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(action: .space, client: sender)
    }

    private func handle(intent: InputKeyIntent, client sender: Any!) -> Bool {
        switch intent {
        case .append(let text):
            rawBuffer.append(text)
            invalidateSuggestion()
            refreshComposition()
            updateNativeCandidates()
            refreshSuggestion(client: sender)
            return true
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                return false
            }
            rawBuffer.removeLast()
            invalidateSuggestion()
            refreshComposition()
            updateNativeCandidates()
            refreshSuggestion(client: sender)
            return true
        case .action(let action):
            return commit(action: action, client: sender)
        case .ignored:
            return false
        }
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
                self.refreshComposition()
                self.updateNativeCandidates()
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
            refreshComposition()
            return true
        case .keepComposition:
            refreshComposition()
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

        if let selectedNativeCandidate {
            switch selectedNativeCandidate.kind {
            case .rawInput:
                switch action {
                case .space, .tab:
                    return .commit(selectedNativeCandidate.text)
                case .optionR:
                    return .polishRequested(selectedNativeCandidate.text)
                case .optionNumber:
                    return .noAction
                }
            case .prefixCandidate(let index):
                if suggestion.prefixCandidates.indices.contains(index) {
                    if index != 0 {
                        switch action {
                        case .space, .tab, .optionNumber:
                            return .commit(suggestion.prefixCandidates[index].text)
                        case .optionR:
                            return .polishRequested(rawBuffer)
                        }
                    }
                    return InputCompositionController().handle(
                        action: action,
                        prefixCandidates: [suggestion.prefixCandidates[index]],
                        continuationCandidates: suggestion.continuationCandidates,
                        originalText: rawBuffer
                    )
                }
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
        refreshComposition()
        hideNativeCandidates()
    }

    private func invalidateSuggestion() {
        lastSuggestion = nil
        lastSuggestionRawInput = nil
        selectedNativeCandidate = nil
        suggestionTask?.cancel()
        suggestionTask = nil
    }

    private func updateNativeCandidates() {
        guard lastSuggestion != nil else {
            displayedNativeCandidates = []
            hideNativeCandidates()
            return
        }
        let selections = candidateListBuilder.candidateSelections(rawInput: rawBuffer, suggestion: lastSuggestion)
        displayedNativeCandidates = selections
        guard !selections.isEmpty else {
            hideNativeCandidates()
            return
        }
        MainActor.assumeIsolated {
            guard let nativeCandidates = nativeCandidateWindow() else {
                return
            }
            nativeCandidates.setCandidateData(selections.map(\.text))
            refreshNativeCandidateWindow(nativeCandidates)
            nativeCandidates.show(kIMKLocateCandidatesBelowHint)
        }
    }

    private func hideNativeCandidates() {
        MainActor.assumeIsolated {
            nativeCandidates?.hide()
        }
        displayedNativeCandidates = []
        selectedNativeCandidate = nil
    }

    @MainActor
    private func nativeCandidateWindow() -> IMKCandidates? {
        if let nativeCandidates {
            return nativeCandidates
        }
        guard let server = server() else {
            return nil
        }
        let candidates = IMKCandidates(
            server: server,
            panelType: kIMKSingleColumnScrollingCandidatePanel
        )
        candidates?.setDismissesAutomatically(false)
        candidates?.setAttributes([IMKCandidatesSendServerKeyEventFirst as String: true])
        candidates?.setSelectionKeys(Self.nativeCandidateSelectionKeyCodes)
        nativeCandidates = candidates
        return candidates
    }

    @MainActor
    private func refreshNativeCandidateWindow(_ nativeCandidates: IMKCandidates) {
        let updateCandidatesSelector = NSSelectorFromString("updateCandidates")
        if nativeCandidates.responds(to: updateCandidatesSelector) {
            nativeCandidates.perform(updateCandidatesSelector)
        } else {
            nativeCandidates.update()
        }
    }

    private func selectNativeCandidate(matching text: String?) {
        guard let text,
              let selection = displayedNativeCandidates.first(where: { $0.text == text }) else {
            selectedNativeCandidate = nil
            return
        }
        selectedNativeCandidate = selection
    }

    private func refreshComposition() {
        super.updateComposition()
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

    private static let textOnlyKeyCode = -1
    private static let nativeCandidateSelectionKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}
#endif
