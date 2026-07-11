import Foundation
import KnowTypeAI
import KnowTypeCore
import OSLog

#if canImport(InputMethodKit)
import AppKit
@preconcurrency import InputMethodKit

private let inputControllerLogger = Logger(
    subsystem: "com.knowtype.inputmethod.KnowType",
    category: "input-controller"
)

enum InputControllerRecognizedEventPolicy {
    static var recognizedEvents: Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }
}

enum InputMethodLexicalProfileRuntime {
    static let store = LexicalProfileStore()
    static let refreshGate = LexicalProfileRefreshGate()
    static let acceptedLearningStore = AIAcceptedLearningStore()
    static let acceptedFeedbackStore = AIAcceptedFeedbackStore()
    static let rimeMaintenanceService = RimeMaintenanceService(
        snapshotProvider: RimeUserDBTextSnapshotProvider()
    )
}

private enum InputMethodInputModeRuntime {
    static let shared = ProcessInputModeStateRuntime(
        initialSymbolWidth: UserDefaultsInputModePreferenceStore.defaultStore()
            .loadPreferences()
            .globalSymbolWidth
    )
}

private enum InputMethodAIRuntime {
    static let contextMemory = AIContextMemoryRuntime(
        providerRegistry: ProviderRuntimeRegistry.shared
    )
}

private final class InputMethodRimePrewarmer: @unchecked Sendable {
    static let shared = InputMethodRimePrewarmer()

    private let lock = NSLock()
    private var didSchedule = false

    private init() {}

    func scheduleOnce() {
        lock.lock()
        guard !didSchedule else {
            lock.unlock()
            return
        }
        didSchedule = true
        lock.unlock()

        Task.detached(priority: .utility) {
            _ = RimeConversionEngine.prewarmNativeSession()
        }
    }
}

@objc(KnowTypeInputController)
public final class KnowTypeInputController: IMKInputController, CandidatePanelInteractionHandling, @unchecked Sendable {
    private let coordinator: InputControllerCoordinator
    private let hostAdapter: IMKInputControllerHostAdapter
    private let runtimePreferenceStore: any InputMethodRuntimePreferenceStore
    @MainActor private lazy var candidatePanelController = CandidatePanelWindowController(interactionHandler: self)
    @MainActor private var preferencesWindowController: KnowTypePreferencesWindowController?

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let startupDebugStartedAt = Date()
        let aiDiagnosticSink = OSLogAIRecommendationDiagnosticSink()
        let aiProviderAvailability = AIRecommendationProviderAvailabilityState()
        let aiRecommendationRuntime = LazyDefaultAIRecommendationRuntime(
            diagnosticSink: aiDiagnosticSink,
            providerAvailability: aiProviderAvailability,
            debounceMilliseconds: 0
        )
        let aiContextEventRecorder: any AIContextEventRecording = InputMethodAIRuntime.contextMemory
        let runtimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore()
        let runtimePreferences = runtimePreferenceStore.loadPreferences()
        let inputModePreferenceStore = UserDefaultsInputModePreferenceStore.defaultStore()
        let historyPersistence = (try? FileUserSelectionHistoryStore.defaultStore(createDirectory: false))
            .map(UserSelectionHistoryPersistence.init(store:))
        let hostAdapter = IMKInputControllerHostAdapter()
        let initialClient = Self.inputControllerClient(from: inputClient)

        self.hostAdapter = hostAdapter
        self.runtimePreferenceStore = runtimePreferenceStore
        self.coordinator = InputControllerCoordinator(
            provider: nil,
            inputModePreferenceStore: inputModePreferenceStore,
            inputModeStateRuntime: InputMethodInputModeRuntime.shared,
            runtimePreferenceStore: runtimePreferenceStore,
            initialRuntimePreferences: runtimePreferences,
            initialAppBundleID: initialClient?.bundleIdentifier,
            userSelectionHistoryPersistence: historyPersistence,
            aiRecommendationProvider: aiRecommendationRuntime,
            aiRecommendationProviderAvailability: aiProviderAvailability,
            aiContextEventRecorder: aiContextEventRecorder,
            aiAcceptedLearning: InputMethodLexicalProfileRuntime.acceptedLearningStore,
            aiAcceptedFeedback: InputMethodLexicalProfileRuntime.acceptedFeedbackStore,
            aiDiagnosticSink: aiDiagnosticSink,
            lexicalProfileStore: InputMethodLexicalProfileRuntime.store,
            lexicalProfileRefreshGate: InputMethodLexicalProfileRuntime.refreshGate,
            rimeUserDBTextProvider: InputMethodLexicalProfileRuntime.rimeMaintenanceService,
            host: hostAdapter,
            anchorResolver: CandidateAnchorResolver(
                screenProvider: AppKitScreenGeometryProvider(),
                accessibilityProvider: SystemAccessibilityAnchorProvider()
            )
        )
        super.init(server: server, delegate: delegate, client: inputClient)
        hostAdapter.controller = self
        InputMethodRimePrewarmer.shared.scheduleOnce()
        inputControllerLogger.notice("KnowTypeInputController initialized client=\(initialClient?.bundleIdentifier ?? "<unknown>", privacy: .public)")
        let elapsedMs = Date().timeIntervalSince(startupDebugStartedAt) * 1_000
        InputDebugDiagnostics.emit(
            category: .startup,
            fields: [
                .init(.stage, "controller_init"),
                .init(.elapsedMs, String(format: "%.1f", elapsedMs)),
                .init(.bundleID, initialClient?.bundleIdentifier ?? "unknown"),
                .init(.reason, "rime=deferred;provider=deferred;learning=read_only")
            ],
            logger: inputControllerLogger
        )
    }

    public override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: keyCode,
            modifiers: modifierSet(from: flags)
        )

        let handled = coordinator.handle(stroke: stroke, client: Self.inputControllerClient(from: sender))
        inputControllerLogger.debug("inputText key=\(keyCode, privacy: .public) handled=\(handled, privacy: .public)")
        return handled
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
            client: effectiveInputControllerClient(from: client())
        )
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        InputControllerRecognizedEventPolicy.recognizedEvents
    }

    public override func menu() -> NSMenu! {
        KnowTypeInputMethodMenuBuilder.makeMenu(
            target: self,
            runtimePreferences: runtimePreferenceStore.loadPreferences(),
            inputModeState: coordinator.currentInputModeState()
        )
    }

    public override func showPreferences(_ sender: Any!) {
        MainActor.assumeIsolated {
            if preferencesWindowController == nil {
                preferencesWindowController = KnowTypePreferencesWindowController()
            }
            preferencesWindowController?.showWindow(nil)
        }
    }

    @objc func toggleAIContinuation(_ sender: Any!) {
        do {
            let preferences = try KnowTypeInputMethodMenuBuilder.toggleAIContinuation(in: runtimePreferenceStore)
            coordinator.reloadRuntimePreferencesForExternalChange()
            inputControllerLogger.notice("AI continuation menu toggle enabled=\(preferences.cloudContinuationEnabled, privacy: .public)")
        } catch {
            inputControllerLogger.error("AI continuation menu toggle failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    @objc func openKnowTypeLogs(_ sender: Any!) {
        openDirectory(Self.knowTypeLogsURL)
    }

    @objc func openKnowTypeSupportFolder(_ sender: Any!) {
        openDirectory(Self.knowTypeSupportURL)
    }

    @objc func openRimeUserFolder(_ sender: Any!) {
        openDirectory(NativeRimeConfiguration.defaultConfiguration()?.userDataURL ?? Self.defaultRimeUserURL)
    }

    @objc func showAbout(_ sender: Any!) {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            let bundle = Bundle.main
            let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
            let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "KnowType",
                .applicationVersion: shortVersion,
                .version: buildVersion
            ])
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
        let handled = coordinator.handle(stroke: stroke, client: Self.inputControllerClient(from: sender))
        inputControllerLogger.debug("handle event key=\(event.keyCode, privacy: .public) handled=\(handled, privacy: .public)")
        return handled
    }

    public override func commitComposition(_ sender: Any!) {
        coordinator.commitComposition(client: effectiveInputControllerClient(from: sender))
    }

    public override func hidePalettes() {
        super.hidePalettes()
        coordinator.hidePalettes()
    }

    public override func deactivateServer(_ sender: Any!) {
        coordinator.deactivateServer(
            client: Self.inputControllerClient(from: sender) ?? currentInputControllerClient
        )
        super.deactivateServer(sender)
    }

    public override func inputControllerWillClose() {
        coordinator.inputControllerWillClose()
        super.inputControllerWillClose()
    }

    private func openDirectory(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            inputControllerLogger.error("Could not open directory \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    fileprivate var currentInputControllerClient: InputControllerClient? {
        Self.inputControllerClient(from: client())
    }

    fileprivate func performSuperUpdateComposition() {
        super.updateComposition()
    }

    fileprivate func applyCandidatePanelFrame(_ frame: CandidatePanelFrame, locale: KnowTypeLocale) {
        MainActor.assumeIsolated {
            candidatePanelController.apply(frame: frame, locale: locale)
        }
    }

    func candidatePanelDidHover(_ selection: CandidatePanelSelection) {
        coordinator.hoverCandidatePanelSelection(selection)
    }

    func candidatePanelDidCommit(_ selection: CandidatePanelSelection) {
        coordinator.commitCandidatePanelSelection(
            selection,
            client: effectiveInputControllerClient(from: client())
        )
    }

    func candidatePanelDidScroll(_ navigation: InputCandidateNavigation) {
        _ = coordinator.scrollCandidatePanel(navigation)
    }

    static func inputControllerClient(from sender: Any!) -> InputControllerClient? {
        guard let client = sender as? IMKTextInput else {
            return nil
        }
        return IMKInputControllerClientAdapter(client: client)
    }

    private func effectiveInputControllerClient(from sender: Any!) -> InputControllerClient? {
        Self.inputControllerClient(from: sender) ?? currentInputControllerClient
    }

    private func modifierSet(from flags: Int) -> Set<InputModifier> {
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(flags))
        var modifiers: Set<InputModifier> = []
        if eventFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
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

    private static var knowTypeSupportURL: URL {
        libraryURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("KnowType", isDirectory: true)
    }

    private static var knowTypeLogsURL: URL {
        libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("KnowType", isDirectory: true)
    }

    private static var defaultRimeUserURL: URL {
        knowTypeSupportURL.appendingPathComponent("Rime", isDirectory: true)
    }

    private static var libraryURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
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

    func applyCandidatePanelFrame(_ frame: CandidatePanelFrame, locale: KnowTypeLocale) {
        controller?.applyCandidatePanelFrame(frame, locale: locale)
    }

    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            operation()
        }
    }

    func schedulePostInsertCaretVerification(_ operation: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async {
            operation()
        }
    }
}
#endif
