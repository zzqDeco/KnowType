import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore

struct InputCandidatePanelPublicationSnapshot: Sendable, Equatable {
    var rawInput: String
    var compositionID: Int
    var rawRevision: Int
    var suggestion: SuggestionResponse?
    var lastSuggestionRawInput: String?
    var nativeIsActive: Bool
    var nativeHasActiveInput: Bool
}

struct InputCandidatePanelPublicationRequest: Sendable, Equatable {
    var snapshot: InputCandidatePanelPublicationSnapshot
    var anchorResult: CandidateAnchorResult
    var placementPreference: CandidatePanelPlacementPreference
    var preeditDisplayText: String?
    var aiRecommendation: AIRecommendationState
    var savedPageSize: Int
    var effectivePageSize: Int
    var layoutMode: CandidatePanelLayoutMode
    var preferredSelection: CandidatePanelSelection?
}

struct InputCandidatePanelReanchorSnapshot: Sendable, Equatable {
    var rawInput: String
    var compositionID: Int
    var hasActiveComposition: Bool
}

struct InputCandidatePanelPublicationResult: Sendable, Equatable {
    var state: CandidatePanelState
    var selection: CandidatePanelSelection?
    var isVisible: Bool
    var visibilityReason: CandidatePanelVisibilityReason
    var didHide: Bool
}

final class InputCandidatePanelPublicationRuntime: @unchecked Sendable {
    private weak var host: InputControllerHost?
    private let presenter: CandidatePanelPresenter
    private let taskSupervisor: InputTaskSupervisor
    private let traceStartupEvent: @Sendable (_ event: String, _ details: String) -> Void
    private var panelState = CandidatePanelState()
    private var panelUpdateGeneration = 0
    private var panelUpdateTask: Task<Void, Never>?
    private var delayedReanchorGeneration = 0
    private var didTraceFirstCandidatePanelMaterialization = false

    init(
        host: InputControllerHost,
        taskSupervisor: InputTaskSupervisor,
        traceStartupEvent: @escaping @Sendable (_ event: String, _ details: String) -> Void = { _, _ in }
    ) {
        self.host = host
        self.presenter = CandidatePanelPresenter(host: host)
        self.taskSupervisor = taskSupervisor
        self.traceStartupEvent = traceStartupEvent
    }

    var state: CandidatePanelState {
        panelState
    }

    @discardableResult
    func publishImmediately(
        snapshot: InputCandidatePanelPublicationSnapshot,
        request: () -> InputCandidatePanelPublicationRequest,
        locale: KnowTypeLocale
    ) -> InputCandidatePanelPublicationResult {
        let generation = nextPanelGeneration()
        panelUpdateTask?.cancel()
        panelUpdateTask = nil
        taskSupervisor.cancel(.panelRender)
        guard canPublish(snapshot: snapshot) else {
            return applyHiddenFrame(
                reason: suppressionReason(snapshot: snapshot),
                presentationGeneration: generation,
                compositionID: snapshot.compositionID,
                rawRevision: snapshot.rawRevision,
                rawLength: snapshot.rawInput.count,
                locale: locale,
                cancelPendingPublication: false
            )
        }
        return publish(request: request(), locale: locale, presentationGeneration: generation)
    }

    @discardableResult
    func publish(
        snapshot: InputCandidatePanelPublicationSnapshot,
        enablesAsyncRefresh: Bool,
        request: @escaping @Sendable () -> InputCandidatePanelPublicationRequest?,
        currentSnapshot: @escaping @Sendable () -> InputCandidatePanelPublicationSnapshot,
        locale: KnowTypeLocale,
        onPublication: @escaping @MainActor @Sendable (InputCandidatePanelPublicationResult) -> Void
    ) -> InputCandidatePanelPublicationResult? {
        guard canPublish(snapshot: snapshot) else {
            let result = hide(
                reason: suppressionReason(snapshot: snapshot),
                compositionID: snapshot.compositionID,
                rawRevision: snapshot.rawRevision,
                rawLength: snapshot.rawInput.count,
                locale: locale
            )
            return result
        }
        guard enablesAsyncRefresh else {
            guard let request = request() else {
                return nil
            }
            let generation = nextPanelGeneration()
            panelUpdateTask?.cancel()
            panelUpdateTask = nil
            taskSupervisor.cancel(.panelRender)
            let result = publish(
                request: request,
                locale: locale,
                presentationGeneration: generation
            )
            return result
        }

        let generation = nextPanelGeneration()
        panelUpdateTask?.cancel()
        taskSupervisor.cancel(.panelRender)
        let task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.panelUpdateGeneration == generation else {
                return
            }
            let current = currentSnapshot()
            guard current.rawInput == snapshot.rawInput,
                  current.rawRevision == snapshot.rawRevision,
                  current.compositionID == snapshot.compositionID else {
                return
            }
            guard let resolvedRequest = request() else {
                return
            }
            guard self.canPublish(snapshot: resolvedRequest.snapshot) else {
                let result = self.applyHiddenFrame(
                    reason: self.suppressionReason(snapshot: resolvedRequest.snapshot),
                    presentationGeneration: generation,
                    compositionID: resolvedRequest.snapshot.compositionID,
                    rawRevision: resolvedRequest.snapshot.rawRevision,
                    rawLength: resolvedRequest.snapshot.rawInput.count,
                    locale: locale,
                    cancelPendingPublication: false
                )
                onPublication(result)
                return
            }
            let result = self.publish(
                request: resolvedRequest,
                locale: locale,
                presentationGeneration: generation
            )
            onPublication(result)
        }
        panelUpdateTask = task
        taskSupervisor.replace(.panelRender, with: task)
        return nil
    }

    @discardableResult
    func hide(
        reason: CandidatePanelVisibilityReason,
        compositionID: Int,
        rawRevision: Int,
        rawLength: Int,
        locale: KnowTypeLocale
    ) -> InputCandidatePanelPublicationResult {
        applyHiddenFrame(
            reason: reason,
            presentationGeneration: nextPanelGeneration(),
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawLength,
            locale: locale,
            cancelPendingPublication: true
        )
    }

    @discardableResult
    private func applyHiddenFrame(
        reason: CandidatePanelVisibilityReason,
        presentationGeneration: Int,
        compositionID: Int,
        rawRevision: Int,
        rawLength: Int,
        locale: KnowTypeLocale,
        cancelPendingPublication: Bool
    ) -> InputCandidatePanelPublicationResult {
        delayedReanchorGeneration += 1
        if cancelPendingPublication {
            panelUpdateTask?.cancel()
            panelUpdateTask = nil
            taskSupervisor.cancel(.panelRender)
        }
        panelState.hide()
        presenter.hide(
            reason: reason,
            presentationGeneration: presentationGeneration,
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawLength,
            locale: locale
        )
        return result(reason: reason, didHide: true)
    }

    @discardableResult
    func selectVisibleRow(_ selection: CandidatePanelSelection) -> InputCandidatePanelPublicationResult? {
        guard panelState.selectVisibleRow(selection) else {
            return nil
        }
        return result(reason: .compositionActive, didHide: false)
    }

    @discardableResult
    func selectVisiblePrefixCandidate(shortcutNumber number: Int) -> InputCandidatePanelPublicationResult? {
        guard panelState.selectVisiblePrefixCandidate(shortcutNumber: number) != nil else {
            return nil
        }
        return result(reason: .compositionActive, didHide: false)
    }

    @discardableResult
    func moveLocalSelection(_ navigation: InputCandidateNavigation) -> InputCandidatePanelPublicationResult? {
        guard panelState.moveSelection(navigation) else {
            return nil
        }
        return result(reason: .compositionActive, didHide: false)
    }

    func applyCurrentFrame(
        reason: CandidatePanelVisibilityReason,
        compositionID: Int,
        rawRevision: Int,
        rawLength: Int,
        locale: KnowTypeLocale
    ) {
        presenter.apply(
            CandidatePanelFrame(
                presentationGeneration: currentPanelGeneration(),
                compositionID: compositionID,
                rawRevision: rawRevision,
                rawLength: rawLength,
                panelModel: panelState,
                anchorSource: panelState.windowState.anchorSource,
                visibilityReason: reason
            ),
            locale: locale
        )
    }

    func scheduleDelayedReanchor(
        rawInput: String,
        compositionID: Int,
        currentSnapshot: @escaping @Sendable () -> InputCandidatePanelReanchorSnapshot,
        publish: @escaping @Sendable () -> Void
    ) {
        delayedReanchorGeneration += 1
        let generation = delayedReanchorGeneration
        host?.scheduleDelayedReanchor { [weak self] in
            guard let self,
                  self.delayedReanchorGeneration == generation else {
                return
            }
            let current = currentSnapshot()
            guard CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                snapshotRawInput: rawInput,
                currentRawInput: current.rawInput,
                snapshotCompositionID: compositionID,
                currentCompositionID: current.compositionID,
                hasActiveComposition: current.hasActiveComposition
            ) else {
                return
            }
            publish()
        }
    }

    private func publish(
        request: InputCandidatePanelPublicationRequest,
        locale: KnowTypeLocale,
        presentationGeneration: Int
    ) -> InputCandidatePanelPublicationResult {
        let isDisplayable = request.anchorResult.source != .none
        panelState.update(
            rawInput: request.snapshot.rawInput,
            suggestion: request.snapshot.suggestion,
            anchorRect: request.anchorResult.rect,
            anchorSource: request.anchorResult.source,
            isDisplayable: isDisplayable,
            pageSize: request.effectivePageSize,
            layoutMode: request.layoutMode,
            placementPreference: request.placementPreference,
            preeditDisplayText: request.preeditDisplayText,
            aiRecommendation: request.aiRecommendation,
            preferredSelection: request.preferredSelection
        )
        traceCandidatePanelUpdate(
            savedPageSize: request.savedPageSize,
            effectivePageSize: request.effectivePageSize,
            locale: locale
        )
        traceFirstCandidatePanelMaterializationIfNeeded(locale: locale)
        let reason: CandidatePanelVisibilityReason = panelState.windowState.isVisible
            ? .compositionActive
            : .layoutImpossible
        presenter.apply(
            CandidatePanelFrame(
                presentationGeneration: presentationGeneration,
                compositionID: request.snapshot.compositionID,
                rawRevision: request.snapshot.rawRevision,
                rawLength: request.snapshot.rawInput.count,
                panelModel: panelState,
                anchorSource: panelState.windowState.anchorSource,
                visibilityReason: reason
            ),
            locale: locale
        )
        return result(reason: reason, didHide: false)
    }

    private func nextPanelGeneration() -> Int {
        panelUpdateGeneration += 1
        return panelUpdateGeneration
    }

    private func currentPanelGeneration() -> Int {
        if panelUpdateGeneration == 0 {
            return nextPanelGeneration()
        }
        return panelUpdateGeneration
    }

    private func canPublish(snapshot: InputCandidatePanelPublicationSnapshot) -> Bool {
        guard !snapshot.rawInput.isEmpty else {
            return false
        }
        if snapshot.suggestion != nil,
           let lastSuggestionRawInput = snapshot.lastSuggestionRawInput,
           lastSuggestionRawInput != snapshot.rawInput {
            return false
        }
        if snapshot.nativeIsActive {
            return snapshot.nativeHasActiveInput || !snapshot.rawInput.isEmpty
        }
        return true
    }

    private func suppressionReason(
        snapshot: InputCandidatePanelPublicationSnapshot
    ) -> CandidatePanelVisibilityReason {
        guard !snapshot.rawInput.isEmpty else {
            return .rawEmpty
        }
        if snapshot.suggestion != nil,
           let lastSuggestionRawInput = snapshot.lastSuggestionRawInput,
           lastSuggestionRawInput != snapshot.rawInput {
            return .staleUpdate
        }
        return .layoutImpossible
    }

    private func result(
        reason: CandidatePanelVisibilityReason,
        didHide: Bool
    ) -> InputCandidatePanelPublicationResult {
        InputCandidatePanelPublicationResult(
            state: panelState,
            selection: panelState.windowState.selection,
            isVisible: panelState.windowState.isVisible,
            visibilityReason: reason,
            didHide: didHide
        )
    }

    private func traceFirstCandidatePanelMaterializationIfNeeded(locale: KnowTypeLocale) {
        guard panelState.windowState.isVisible,
              !didTraceFirstCandidatePanelMaterialization else {
            return
        }
        didTraceFirstCandidatePanelMaterialization = true
        let rowCount = CandidatePanelRenderer(locale: locale)
            .render(
                panelState.windowState.viewModel,
                selected: panelState.windowState.selection,
                paging: panelState.windowState.paging
            )
            .rows
            .count
        traceStartupEvent(
            "first_candidate_panel_materialization",
            "anchorSource=\(panelState.windowState.anchorSource.rawValue) renderRows=\(rowCount)"
        )
    }

    private func traceCandidatePanelUpdate(
        savedPageSize: Int,
        effectivePageSize: Int,
        locale: KnowTypeLocale
    ) {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_PANEL_DEBUG"] == "1" else {
            return
        }
        let windowState = panelState.windowState
        let rowCount = CandidatePanelRenderer(locale: locale)
            .render(
                windowState.viewModel,
                selected: windowState.selection,
                paging: windowState.paging
            )
            .rows
            .count
        fputs(
            "KnowType panel: layoutMode=\(windowState.layoutMode.rawValue) savedPageSize=\(savedPageSize) effectivePageSize=\(effectivePageSize) anchorSource=\(windowState.anchorSource.rawValue) visible=\(windowState.isVisible) renderRows=\(rowCount)\n",
            stderr
        )
    }
}
