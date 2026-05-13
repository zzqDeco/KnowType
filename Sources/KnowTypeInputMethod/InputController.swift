import Foundation
import KnowTypeCore
import KnowTypeProviders

#if canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, @unchecked Sendable {
    private let sessionController: InputSessionController
    private let keyMapper = InputKeyCommandMapper()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let customCandidateSelectionPolicy = CustomCandidateSelectionPolicy()
    private var rawBuffer = ""
    private var lastSuggestion: SuggestionResponse?
    private var lastSuggestionRawInput: String?
    private var locale: KnowTypeLocale = .mixed
    private var suggestionTask: Task<Void, Never>?
    private var nativeCandidates: IMKCandidates?
    private var displayedNativeCandidates: [InputCandidateSelection] = []
    private var selectedNativeCandidate: InputCandidateSelection?
    private var candidatePanelState = CandidatePanelState()
    @MainActor private lazy var candidatePanelController = CandidatePanelWindowController()

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.sessionController = InputSessionController(
            provider: ProviderRuntimeLoader.loadDefaultProvider()
        )
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: keyCode,
            modifiers: modifierSet(from: flags)
        )

        return handle(stroke: stroke, client: sender)
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
        return handle(stroke: stroke, client: sender)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(action: .space, client: sender)
    }

    public override func hidePalettes() {
        super.hidePalettes()
        hideNativeCandidates()
        hideCandidatePanel()
    }

    public override func inputControllerWillClose() {
        hideNativeCandidates()
        hideCandidatePanel()
        super.inputControllerWillClose()
    }

    private func handle(stroke: InputKeyStroke, client sender: Any!) -> Bool {
        if handleCustomCandidateSelection(stroke: stroke, client: sender) {
            return true
        }
        return handle(intent: keyMapper.intent(for: stroke), client: sender)
    }

    private func handle(intent: InputKeyIntent, client sender: Any!) -> Bool {
        switch intent {
        case .append(let text):
            rawBuffer.append(text)
            invalidateSuggestion()
            publishLocalSuggestion(client: sender)
            refreshSuggestion(client: sender)
            return true
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                return false
            }
            rawBuffer.removeLast()
            invalidateSuggestion()
            publishLocalSuggestion(client: sender)
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
                let currentClient = self.client()
                guard SuggestionPublicationGuard.shouldPublish(
                    requestedRawInput: rawInput,
                    currentRawInput: self.rawBuffer,
                    isCancelled: Task.isCancelled
                ) else {
                    return
                }
                self.lastSuggestion = suggestion
                self.lastSuggestionRawInput = rawInput
                self.refreshComposition(client: currentClient)
                if self.updateNativeCandidates(client: currentClient) {
                    self.hideCandidatePanel()
                } else {
                    self.updateCandidatePanel(suggestion: suggestion, client: currentClient)
                }
            }
        }
    }

    private func appBundleIdentifier(client sender: Any!) -> String? {
        (sender as? IMKTextInput)?.bundleIdentifier()
    }

    private func publishLocalSuggestion(client sender: Any!) {
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            lastSuggestion = nil
            lastSuggestionRawInput = nil
            refreshComposition(client: sender)
            if updateNativeCandidates(client: sender) {
                hideCandidatePanel()
            } else {
                updateCandidatePanel(suggestion: nil, client: sender)
            }
            return
        }

        let context = InputContext(
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: sender),
            locale: locale
        )
        let suggestion = InputMethodPipeline.localSuggestions(for: context)
        lastSuggestion = suggestion
        lastSuggestionRawInput = rawBuffer
        refreshComposition(client: sender)
        if updateNativeCandidates(client: sender) {
            hideCandidatePanel()
        } else {
            updateCandidatePanel(suggestion: suggestion, client: sender)
        }
    }

    @discardableResult
    private func commit(action: InputAction, client sender: Any!) -> Bool {
        let result = commitResult(for: action, client: sender)
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
            insert(text, client: sender)
            resetComposition(client: sender)
            return true
        case .requestPolishAndKeepComposition(let text):
            Task { [sessionController] in
                await sessionController.requestPolish(rawInput: text)
            }
            refreshComposition(client: sender)
            return true
        case .keepComposition:
            refreshComposition(client: sender)
            return true
        case .noAction:
            return InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: !rawBuffer.isEmpty)
        }
    }

    private func commitResult(for action: InputAction, client sender: Any!) -> InputCommitResult {
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
                let context = InputContext(
                    rawInput: rawBuffer,
                    appBundleID: appBundleIdentifier(client: sender),
                    locale: locale
                )
                let suggestion = InputMethodPipeline.localSuggestions(for: context)
                return InputCompositionController().handle(
                    action: action,
                    prefixCandidates: suggestion.prefixCandidates,
                    continuationCandidates: suggestion.continuationCandidates,
                    originalText: rawBuffer
                )
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
            case .continuationCandidate(let index):
                guard suggestion.continuationCandidates.indices.contains(index) else {
                    return .noAction
                }
                switch action {
                case .space, .tab, .optionNumber:
                    return InputCompositionController().handle(
                        action: .optionNumber(index + 1),
                        prefixCandidates: suggestion.prefixCandidates,
                        continuationCandidates: suggestion.continuationCandidates,
                        originalText: rawBuffer
                    )
                case .optionR:
                    return .polishRequested(rawBuffer)
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
        if let client = sender as? IMKTextInput {
            client.insertText(text, replacementRange: replacementRangeForCommit(client))
        }
    }

    private func resetComposition(client sender: Any!) {
        rawBuffer = ""
        invalidateSuggestion()
        hideNativeCandidates()
        hideCandidatePanel()
    }

    private func invalidateSuggestion() {
        lastSuggestion = nil
        lastSuggestionRawInput = nil
        selectedNativeCandidate = nil
        suggestionTask?.cancel()
        suggestionTask = nil
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, client sender: Any!) {
        guard !rawBuffer.isEmpty || suggestion != nil else {
            hideCandidatePanel()
            return
        }
        updateCandidatePanel(suggestion: suggestion, anchorRect: candidateAnchorRect(client: sender))
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, anchorRect: CGRect) {
        candidatePanelState.update(rawInput: rawBuffer, suggestion: suggestion, anchorRect: anchorRect)
        MainActor.assumeIsolated {
            candidatePanelController.update(state: candidatePanelState, locale: locale)
        }
    }

    private func hideCandidatePanel() {
        candidatePanelState.hide()
        MainActor.assumeIsolated {
            candidatePanelController.hide()
        }
    }

    private func candidateAnchorRect(client sender: Any!) -> CGRect {
        guard let client = sender as? IMKTextInput else {
            return .zero
        }
        let characterRange = CandidateAnchorPolicy.characterRange(
            selectedRange: client.selectedRange(),
            markedRange: client.markedRange()
        )
        let firstRect = client.firstRect(
            forCharacterRange: characterRange,
            actualRange: nil
        )
        if isUsableAnchorRect(firstRect) {
            return firstRect
        }

        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        return isUsableAnchorRect(lineRect) ? lineRect : .zero
    }

    private func handleCustomCandidateSelection(stroke: InputKeyStroke, client sender: Any!) -> Bool {
        switch customCandidateSelectionPolicy.decision(
            for: stroke,
            rawInput: rawBuffer,
            suggestion: lastSuggestion,
            suggestionRawInput: lastSuggestionRawInput
        ) {
        case .commitRawInput:
            insert(rawBuffer, client: sender)
            resetComposition(client: sender)
            return true
        case .commitPrefixCandidate(let index):
            guard let suggestion = lastSuggestion,
                  suggestion.prefixCandidates.indices.contains(index) else {
                return false
            }
            insert(suggestion.prefixCandidates[index].text, client: sender)
            resetComposition(client: sender)
            return true
        case .passThrough:
            return false
        }
    }

    @discardableResult
    private func updateNativeCandidates(client sender: Any!) -> Bool {
        let selections = candidateListBuilder.candidateSelections(rawInput: rawBuffer, suggestion: lastSuggestion)
        displayedNativeCandidates = selections
        selectedNativeCandidate = nil
        guard !selections.isEmpty,
              nativeCandidates != nil || server() != nil else {
            hideNativeCandidates()
            return false
        }
        let topLeft = nativeCandidateTopLeft(client: sender)
        let candidateStrings = selections.map(\.text)

        return MainActor.assumeIsolated { () -> Bool in
            guard let nativeCandidates = ensureNativeCandidates() else {
                return false
            }
            nativeCandidates.setCandidateData(candidateStrings)
            nativeCandidates.update()
            if let topLeft {
                nativeCandidates.setCandidateFrameTopLeft(topLeft)
                nativeCandidates.show()
            } else {
                nativeCandidates.show(kIMKLocateCandidatesBelowHint)
            }
            return true
        }
    }

    @MainActor
    private func ensureNativeCandidates() -> IMKCandidates? {
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
        candidates?.setSelectionKeys([18, 19, 20, 21, 23, 22, 26, 28, 25])
        candidates?.setDismissesAutomatically(false)
        candidates?.setAttributes([
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 15),
            IMKCandidatesSendServerKeyEventFirst as String: true,
            IMKCandidatesOpacityAttributeName as String: 1.0
        ])
        nativeCandidates = candidates
        return candidates
    }

    private func hideNativeCandidates() {
        displayedNativeCandidates = []
        selectedNativeCandidate = nil
        MainActor.assumeIsolated {
            nativeCandidates?.hide()
            nativeCandidates?.setCandidateData([])
        }
    }

    private func nativeCandidateTopLeft(client sender: Any!) -> NSPoint? {
        let anchorRect = candidateAnchorRect(client: sender)
        guard isUsableAnchorRect(anchorRect) else {
            return nil
        }
        return NSPoint(x: anchorRect.minX, y: anchorRect.minY - 4)
    }

    private func selectNativeCandidate(matching text: String?) {
        guard let text,
              let selection = displayedNativeCandidates.first(where: { $0.text == text }) else {
            selectedNativeCandidate = nil
            return
        }
        selectedNativeCandidate = selection
    }

    private func refreshComposition(client sender: Any!) {
        guard let client = sender as? IMKTextInput else {
            super.updateComposition()
            return
        }

        let markedText = (lastSuggestion?.prefixCandidates.first?.text).flatMap { $0.isEmpty ? nil : $0 } ?? rawBuffer
        guard !markedText.isEmpty else {
            clearMarkedText(client)
            return
        }

        let replacement = activeMarkedRange(for: client) ?? NSRange(location: NSNotFound, length: NSNotFound)
        client.setMarkedText(
            markedText,
            selectionRange: NSRange(location: (markedText as NSString).length, length: 0),
            replacementRange: replacement
        )
    }

    private func clearMarkedText(_ client: IMKTextInput) {
        guard let markedRange = activeMarkedRange(for: client) else {
            super.updateComposition()
            return
        }
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: markedRange
        )
    }

    private func replacementRangeForCommit(_ client: IMKTextInput) -> NSRange {
        activeMarkedRange(for: client) ?? NSRange(location: NSNotFound, length: NSNotFound)
    }

    private func activeMarkedRange(for client: IMKTextInput) -> NSRange? {
        let markedRange = client.markedRange()
        guard markedRange.location != NSNotFound,
              markedRange.length != NSNotFound else {
            return nil
        }
        return markedRange
    }

    private func isUsableAnchorRect(_ rect: CGRect) -> Bool {
        !rect.isNull
            && !rect.isInfinite
            && rect != .zero
            && rect.minX.isFinite
            && rect.minY.isFinite
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
}
#endif
