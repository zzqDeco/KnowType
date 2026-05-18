import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

#if canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, @unchecked Sendable {
    private let coordinator: InputControllerCoordinator
    private let hostAdapter: IMKInputControllerHostAdapter
    @MainActor private lazy var candidatePanelController = CandidatePanelWindowController()
    @MainActor private var preferencesWindowController: KnowTypePreferencesWindowController?

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let provider = ProviderRuntimeLoader.loadDefaultProvider()
        let aiRecommendationRuntime = AIRecommendationRuntime(provider: provider)
        let aiContextMemoryRuntime = AIContextMemoryRuntime(provider: provider)
        let lexiconRuntime = InputMethodLexiconRuntime.defaultRuntime()
        let runtimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore()
        let runtimePreferences = runtimePreferenceStore.loadPreferences()
        let initialLexiconState = lexiconRuntime.initialEngineState(scheme: runtimePreferences.inputScheme)
        let inputModePreferenceStore = UserDefaultsInputModePreferenceStore.defaultStore()
        let historyPersistence = (try? FileUserSelectionHistoryStore.defaultStore())
            .map(UserSelectionHistoryPersistence.init(store:))
        let hostAdapter = IMKInputControllerHostAdapter()
        let initialClient = Self.inputControllerClient(from: inputClient)

        self.hostAdapter = hostAdapter
        self.coordinator = InputControllerCoordinator(
            provider: provider,
            traditionalInputEngine: initialLexiconState.engine,
            lexiconRuntimeSnapshot: initialLexiconState.snapshot,
            lexiconRuntime: lexiconRuntime,
            inputModePreferenceStore: inputModePreferenceStore,
            runtimePreferenceStore: runtimePreferenceStore,
            initialRuntimePreferences: runtimePreferences,
            initialAppBundleID: initialClient?.bundleIdentifier,
            userSelectionHistoryPersistence: historyPersistence,
            aiRecommendationProvider: aiRecommendationRuntime,
            aiContextEventRecorder: aiContextMemoryRuntime,
            host: hostAdapter,
            anchorResolver: CandidateAnchorResolver(
                screenProvider: AppKitScreenGeometryProvider(),
                accessibilityProvider: SystemAccessibilityAnchorProvider()
            )
        )
        super.init(server: server, delegate: delegate, client: inputClient)
        hostAdapter.controller = self
    }

    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: keyCode,
            modifiers: modifierSet(from: flags)
        )

        return coordinator.handle(stroke: stroke, client: Self.inputControllerClient(from: sender))
    }

    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        coordinator.handleText(string, client: Self.inputControllerClient(from: sender))
    }

    public override func composedString(_ sender: Any!) -> Any! {
        coordinator.composedString()
    }

    public override func originalString(_ sender: Any!) -> NSAttributedString! {
        coordinator.originalString()
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        coordinator.candidates()
    }

    public override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        coordinator.candidateSelectionChanged(candidateString?.string)
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        coordinator.candidateSelected(
            candidateString?.string,
            client: Self.inputControllerClient(from: client())
        )
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.keyDown.rawValue
                | NSEvent.EventTypeMask.keyUp.rawValue
                | NSEvent.EventTypeMask.flagsChanged.rawValue
        )
    }

    public override func menu() -> NSMenu! {
        let menu = NSMenu(title: "KnowType")
        let preferencesItem = NSMenuItem(
            title: "KnowType Settings...",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        return menu
    }

    public override func showPreferences(_ sender: Any!) {
        MainActor.assumeIsolated {
            if preferencesWindowController == nil {
                preferencesWindowController = KnowTypePreferencesWindowController()
            }
            preferencesWindowController?.showWindow(nil)
        }
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
        return coordinator.handle(stroke: stroke, client: Self.inputControllerClient(from: sender))
    }

    public override func commitComposition(_ sender: Any!) {
        coordinator.commitComposition(client: Self.inputControllerClient(from: sender))
    }

    public override func hidePalettes() {
        super.hidePalettes()
        coordinator.hidePalettes()
    }

    public override func deactivateServer(_ sender: Any!) {
        coordinator.deactivateServer()
        super.deactivateServer(sender)
    }

    public override func inputControllerWillClose() {
        coordinator.inputControllerWillClose()
        super.inputControllerWillClose()
    }

    fileprivate var currentInputControllerClient: InputControllerClient? {
        Self.inputControllerClient(from: client())
    }

    fileprivate func performSuperUpdateComposition() {
        super.updateComposition()
    }

    fileprivate func updateCandidatePanelWindow(state: CandidatePanelState, locale: KnowTypeLocale) {
        MainActor.assumeIsolated {
            candidatePanelController.update(state: state, locale: locale)
        }
    }

    fileprivate func hideCandidatePanelWindow() {
        MainActor.assumeIsolated {
            candidatePanelController.hide()
        }
    }

    static func inputControllerClient(from sender: Any!) -> InputControllerClient? {
        guard let client = sender as? IMKTextInput else {
            return nil
        }
        return IMKInputControllerClientAdapter(client: client)
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
}

private final class IMKInputControllerHostAdapter: InputControllerHost, @unchecked Sendable {
    fileprivate weak var controller: KnowTypeInputController?

    var currentClient: InputControllerClient? {
        controller?.currentInputControllerClient
    }

    func updateComposition() {
        controller?.performSuperUpdateComposition()
    }

    func updateCandidatePanel(state: CandidatePanelState, locale: KnowTypeLocale) {
        controller?.updateCandidatePanelWindow(state: state, locale: locale)
    }

    func hideCandidatePanel() {
        controller?.hideCandidatePanelWindow()
    }

    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async {
            operation()
        }
    }
}
#endif
