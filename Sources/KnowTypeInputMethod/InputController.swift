import Foundation
import KnowTypeCore
import KnowTypeProviders

#if canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, @unchecked Sendable {
    private let sessionController: InputSessionController
    private let hasProvider: Bool
    private let keyMapper = InputKeyCommandMapper()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver = CandidateAnchorResolver(
        screenProvider: AppKitScreenGeometryProvider(),
        accessibilityProvider: SystemAccessibilityAnchorProvider()
    )
    private var rawBuffer = ""
    private var compositionID = 0
    private var lastSuggestion: SuggestionResponse?
    private var lastSuggestionRawInput: String?
    private var locale: KnowTypeLocale = .mixed
    private var suggestionTask: Task<Void, Never>?
    private var displayedNativeCandidates: [InputCandidateSelection] = []
    private var selectedNativeCandidate: InputCandidateSelection?
    private var candidatePanelState = CandidatePanelState()
    @MainActor private lazy var candidatePanelController = CandidatePanelWindowController()

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let provider = ProviderRuntimeLoader.loadDefaultProvider()
        self.hasProvider = provider != nil
        self.sessionController = InputSessionController(provider: provider)
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
        Int(
            NSEvent.EventTypeMask.keyDown.rawValue
                | NSEvent.EventTypeMask.keyUp.rawValue
                | NSEvent.EventTypeMask.flagsChanged.rawValue
        )
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event,
              let eventKind = inputKeyEventKind(for: event.type) else {
            return false
        }
        let characters = event.modifierFlags.contains(.option)
            ? event.charactersIgnoringModifiers ?? event.characters ?? ""
            : event.characters ?? event.charactersIgnoringModifiers ?? ""
        let stroke = InputKeyStroke(
            text: characters,
            keyCode: Int(event.keyCode),
            modifiers: modifierSet(from: Int(event.modifierFlags.rawValue)),
            eventKind: eventKind
        )
        return handle(stroke: stroke, client: sender)
    }

    public override func commitComposition(_ sender: Any!) {
        commit(action: .space, client: sender)
    }

    public override func hidePalettes() {
        super.hidePalettes()
        hideCandidatePanel()
    }

    public override func deactivateServer(_ sender: Any!) {
        resetAnchorState()
        super.deactivateServer(sender)
    }

    public override func inputControllerWillClose() {
        hideCandidatePanel()
        super.inputControllerWillClose()
    }

    private func handle(stroke: InputKeyStroke, client sender: Any!) -> Bool {
        return handle(intent: keyMapper.intent(for: stroke), client: sender)
    }

    private func handle(intent: InputKeyIntent, client sender: Any!) -> Bool {
        switch intent {
        case .append(let text):
            beginCompositionIfNeeded()
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
            if rawBuffer.isEmpty {
                resetAnchorState()
            }
            invalidateSuggestion()
            publishLocalSuggestion(client: sender)
            refreshSuggestion(client: sender)
            return true
        case .action(let action):
            return commit(action: action, client: sender)
        case .cancelComposition:
            guard !rawBuffer.isEmpty else {
                return false
            }
            resetComposition(client: sender)
            refreshComposition(client: sender)
            return true
        case .selectCandidate(let number):
            if let result = InputSessionCommitPolicy.resultForCandidateNumber(
                number,
                rawInput: rawBuffer,
                suggestion: lastSuggestion,
                suggestionRawInput: lastSuggestionRawInput
            ) {
                return applyCommitResult(result, client: sender)
            }
            beginCompositionIfNeeded()
            rawBuffer.append(String(number))
            invalidateSuggestion()
            publishLocalSuggestion(client: sender)
            refreshSuggestion(client: sender)
            return true
        case .moveCandidateSelection(let navigation):
            return moveCandidateSelection(navigation)
        case .modifierFlagsChanged:
            return false
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
                self.updateCandidatePanel(suggestion: suggestion, client: currentClient)
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
            updateCandidatePanel(suggestion: nil, client: sender)
            return
        }

        let context = InputContext(
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: sender),
            locale: locale
        )
        let suggestion = InputMethodPipeline.localSuggestions(
            for: context,
            includeFallbackContinuations: !hasProvider
        )
        lastSuggestion = suggestion
        lastSuggestionRawInput = rawBuffer
        refreshComposition(client: sender)
        updateCandidatePanel(suggestion: suggestion, client: sender)
    }

    @discardableResult
    private func commit(action: InputAction, client sender: Any!) -> Bool {
        let result = commitResult(for: action, client: sender)
        return applyCommitResult(result, client: sender)
    }

    @discardableResult
    private func applyCommitResult(_ result: InputCommitResult, client sender: Any!) -> Bool {
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
        InputSessionCommitPolicy.result(
            for: action,
            rawInput: rawBuffer,
            suggestion: lastSuggestion,
            suggestionRawInput: lastSuggestionRawInput,
            selectedCandidate: sessionSelection(from: selectedNativeCandidate),
            appBundleID: appBundleIdentifier(client: sender),
            locale: locale
        )
    }

    private func insert(_ text: String, client sender: Any!) {
        if let client = sender as? IMKTextInput {
            client.insertText(text, replacementRange: replacementRangeForCommit(client))
        }
    }

    private func resetComposition(client sender: Any!) {
        rawBuffer = ""
        resetAnchorState()
        invalidateSuggestion()
        hideCandidatePanel()
    }

    private func beginCompositionIfNeeded() {
        if rawBuffer.isEmpty {
            compositionID += 1
            anchorResolver.reset()
        }
    }

    private func resetAnchorState() {
        compositionID += 1
        anchorResolver.reset()
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
        updateCandidatePanel(suggestion: suggestion, anchorRect: candidateAnchorResult(client: sender).rect)
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, anchorRect: CGRect) {
        candidatePanelState.update(rawInput: rawBuffer, suggestion: suggestion, anchorRect: anchorRect)
        selectedNativeCandidate = inputCandidateSelection(
            for: candidatePanelState.windowState.selection,
            in: candidatePanelState.windowState.viewModel
        )
        MainActor.assumeIsolated {
            candidatePanelController.update(state: candidatePanelState, locale: locale)
        }
    }

    private func hideCandidatePanel() {
        candidatePanelState.hide()
        selectedNativeCandidate = nil
        anchorResolver.reset()
        MainActor.assumeIsolated {
            candidatePanelController.hide()
        }
    }

    private func moveCandidateSelection(_ navigation: InputCandidateNavigation) -> Bool {
        guard candidatePanelState.moveSelection(navigation) else {
            return false
        }
        selectedNativeCandidate = inputCandidateSelection(
            for: candidatePanelState.windowState.selection,
            in: candidatePanelState.windowState.viewModel
        )
        MainActor.assumeIsolated {
            candidatePanelController.update(state: candidatePanelState, locale: locale)
        }
        return true
    }

    private func candidateAnchorResult(client sender: Any!) -> CandidateAnchorResult {
        let geometryClient = (sender as? IMKTextInput).map(IMKTextInputGeometryAdapter.init(client:))
        return anchorResolver.resolve(
            client: geometryClient,
            context: CandidateAnchorContext(
                compositionID: compositionID,
                appBundleID: appBundleIdentifier(client: sender)
            )
        )
    }

    private func selectNativeCandidate(matching text: String?) {
        guard let text,
              let selection = displayedNativeCandidates.first(where: { $0.text == text }) else {
            selectedNativeCandidate = nil
            return
        }
        selectedNativeCandidate = selection
    }

    private func inputCandidateSelection(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel
    ) -> InputCandidateSelection? {
        guard let selection else {
            return nil
        }

        switch selection {
        case .rawInput:
            guard !viewModel.rawInput.isEmpty else {
                return nil
            }
            return InputCandidateSelection(text: viewModel.rawInput, kind: .rawInput)
        case .prefixCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.prefixCandidates[index].text,
                kind: .prefixCandidate(index: index)
            )
        case .continuationCandidate(let index):
            guard viewModel.continuationCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.continuationCandidates[index].text,
                kind: .continuationCandidate(index: index)
            )
        }
    }

    private func sessionSelection(from selection: InputCandidateSelection?) -> InputSessionCandidateSelection? {
        guard let selection else {
            return nil
        }
        switch selection.kind {
        case .rawInput:
            return .rawInput
        case .prefixCandidate(let index):
            return .prefixCandidate(index: index)
        case .continuationCandidate(let index):
            return .continuationCandidate(index: index)
        }
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
        scheduleDelayedCandidateReanchor(
            client: client,
            rawInput: rawBuffer,
            compositionID: compositionID
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

    private func scheduleDelayedCandidateReanchor(
        client: IMKTextInput,
        rawInput: String,
        compositionID: Int
    ) {
        let clientObject = client as AnyObject
        DispatchQueue.main.async { [weak self, weak clientObject] in
            guard let self,
                  let client = clientObject as? IMKTextInput,
                  CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                    snapshotRawInput: rawInput,
                    currentRawInput: self.rawBuffer,
                    snapshotCompositionID: compositionID,
                    currentCompositionID: self.compositionID,
                    isPanelVisible: self.candidatePanelState.windowState.isVisible
                  ) else {
                return
            }
            self.updateCandidatePanel(
                suggestion: self.lastSuggestion,
                anchorRect: self.candidateAnchorResult(client: client).rect
            )
        }
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

    private func inputKeyEventKind(for eventType: NSEvent.EventType) -> InputKeyEventKind? {
        switch eventType {
        case .keyDown:
            return .keyDown
        case .keyUp:
            return .keyUp
        case .flagsChanged:
            return .flagsChanged
        default:
            return nil
        }
    }

    private static let textOnlyKeyCode = -1
}
#endif
