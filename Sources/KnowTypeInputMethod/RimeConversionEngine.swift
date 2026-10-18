import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeRimeBridge

public struct ConversionEngineCandidate: Sendable, Equatable {
    public var text: String
    public var comment: String?
    public var index: Int
    public var confidence: Double
    public var source: String

    public init(
        text: String,
        comment: String? = nil,
        index: Int,
        confidence: Double = 1,
        source: String
    ) {
        self.text = text
        self.comment = comment
        self.index = index
        self.confidence = confidence
        self.source = source
    }
}

enum ConversionCandidateSource {
    private static let nativeIndexMarker = "#native-index="

    static func encode(_ source: String, nativeIndex: Int) -> String {
        guard source != "traditional-fallback" else {
            return source
        }
        return "\(source)\(nativeIndexMarker)\(nativeIndex)"
    }

    static func nativeIndex(from source: String) -> Int? {
        guard let range = source.range(of: nativeIndexMarker, options: .backwards) else {
            return nil
        }
        return Int(source[range.upperBound...])
    }
}

public struct ConversionEngineSnapshot: Sendable, Equatable {
    public var rawInput: String
    public var preedit: String
    public var candidates: [ConversionEngineCandidate]
    public var highlightedIndex: Int
    public var pageSize: Int
    public var pageNumber: Int
    public var isLastPage: Bool
    public var engineName: String

    public var hasComposition: Bool {
        !rawInput.isEmpty || !preedit.isEmpty || !candidates.isEmpty
    }

    public init(
        rawInput: String = "",
        preedit: String = "",
        candidates: [ConversionEngineCandidate] = [],
        highlightedIndex: Int = 0,
        pageSize: Int = 0,
        pageNumber: Int = 0,
        isLastPage: Bool = true,
        engineName: String = "rime-unavailable"
    ) {
        self.rawInput = rawInput
        self.preedit = preedit
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.pageSize = pageSize
        self.pageNumber = pageNumber
        self.isLastPage = isLastPage
        self.engineName = engineName
    }
}

public enum ConversionEngineKey: Sendable, Equatable {
    case text(String)
    case space
    case deleteBackward
    case selectCandidateOnCurrentPage(Int)
    case selectCandidate(Int)
    case highlightCandidateOnCurrentPage(Int)
    case pageUp
    case pageDown
    case commitComposition
}

public struct ConversionEngineResult: Sendable, Equatable {
    public var handled: Bool
    public var commitText: String?
    public var snapshot: ConversionEngineSnapshot

    public init(handled: Bool, commitText: String? = nil, snapshot: ConversionEngineSnapshot) {
        self.handled = handled
        self.commitText = commitText
        self.snapshot = snapshot
    }
}

public protocol KnowTypeConversionEngine: Sendable {
    var isNativeActive: Bool { get }
    var snapshot: ConversionEngineSnapshot { get }
    var activeSchemaID: String { get }

    mutating func synchronizeInputMode(_ snapshot: InputModeSnapshot)
    mutating func reset()
    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult
}

public extension KnowTypeConversionEngine {
    var activeSchemaID: String {
        "pinyin_simp"
    }

    mutating func synchronizeInputMode(_: InputModeSnapshot) {}

    func userDBTextSnapshot(schemaID _: String) async throws -> RimeUserDBTextSnapshot {
        throw RimeUserDBTextSnapshotProviderError.unavailable
    }
}

public struct RimeConversionEngine: KnowTypeConversionEngine {
    private let nativeConfiguration: NativeRimeConfiguration?
    private var nativeSession: NativeRimeSession?
    private var nativeSessionCreationAttempted = false
    private var currentSnapshot: ConversionEngineSnapshot
    private var nativeBypassUntilReset = false
    private var nativeRawInputMirror = ""
    private let configuredSchemaID: String
    private var desiredInputModeSnapshot: InputModeSnapshot
    private var appliedNativeInputModeSnapshot: InputModeSnapshot?

    public var isNativeActive: Bool {
        nativeSession != nil && !nativeBypassUntilReset
    }

    public var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    public var activeSchemaID: String {
        nativeSession?.currentSchemaID() ?? configuredSchemaID
    }

    public init(
        traditionalInputEngine _: TraditionalInputEngine? = nil,
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration(),
        inputModeSnapshot: InputModeSnapshot = InputModeStateMachine().snapshot
    ) {
        self.nativeConfiguration = configuration
        self.configuredSchemaID = configuration?.schemaID ?? "pinyin_simp"
        self.nativeSession = nil
        self.currentSnapshot = Self.unavailableSnapshot(rawInput: "")
        self.desiredInputModeSnapshot = inputModeSnapshot
        self.appliedNativeInputModeSnapshot = nil
    }

    @discardableResult
    static func prewarmNativeSession(
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration()
    ) -> Bool {
        guard let configuration else {
            traceStartupEvent("rime_prewarm_done", elapsed: 0, details: "schema=<none> success=false")
            return false
        }
        traceStartupEvent("rime_prewarm_start", details: "schema=\(configuration.schemaID)")
        let startedAt = Date()
        let session = NativeRimeSession.prewarm(configuration: configuration)
        let success = session != nil
        traceStartupEvent(
            "rime_prewarm_done",
            elapsed: Date().timeIntervalSince(startedAt),
            details: "schema=\(configuration.schemaID) success=\(success)"
        )
        return success
    }

    public mutating func reset() {
        nativeBypassUntilReset = false
        nativeRawInputMirror = ""
        nativeSession?.reset()
        currentSnapshot = nativeSession?.snapshot() ?? Self.unavailableSnapshot(rawInput: "")
    }

    public mutating func synchronizeInputMode(_ snapshot: InputModeSnapshot) {
        desiredInputModeSnapshot = snapshot
        synchronizeNativeInputModeIfNeeded()
    }

    public mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        guard InputDebugDiagnostics.isEnabled(.rime) else {
            return processWithoutTracing(key)
        }
        let startedAt = ContinuousClock.now
        let result = processWithoutTracing(key)
        Self.traceProcess(
            key: key,
            result: result,
            elapsedMilliseconds: InputDebugDiagnostics.milliseconds(startedAt.duration(to: .now))
        )
        return result
    }

    private mutating func processWithoutTracing(_ key: ConversionEngineKey) -> ConversionEngineResult {
        if Self.containsNonASCIIText(key) {
            return processRawBypass(key)
        }

        guard !nativeBypassUntilReset else {
            return processUnavailable(key, engineName: "rime-raw-bypass")
        }

        let nativeSession = ensureNativeSession(for: key)
        guard let nativeSession else {
            return processUnavailable(key)
        }

        var result = nativeSession.process(key)
        nativeRawInputMirror = NativeRawInputMirrorPolicy.updatedMirror(
            current: nativeRawInputMirror,
            key: key,
            result: result
        )
        if result.snapshot.rawInput.isEmpty,
           result.snapshot.hasComposition,
           !nativeRawInputMirror.isEmpty {
            result.snapshot.rawInput = nativeRawInputMirror
        }
        currentSnapshot = result.snapshot
        return result
    }

    private mutating func ensureNativeSession(for key: ConversionEngineKey) -> NativeRimeSession? {
        if let nativeSession {
            return nativeSession
        }
        guard !nativeSessionCreationAttempted,
              let nativeConfiguration else {
            return nil
        }
        let startedAt = Date()
        let creationResult = NativeRimeSession.createForeground(
            configuration: nativeConfiguration,
            foregroundMayPreemptSpeculative: Self.shouldPreemptSpeculativePrewarm(
                for: key,
                rawInput: rawMirrorOrSnapshotInput()
            )
        )
        let success: Bool
        let details: String
        switch creationResult {
        case .created(let session):
            nativeSessionCreationAttempted = true
            nativeSession = session
            appliedNativeInputModeSnapshot = nil
            synchronizeNativeInputModeIfNeeded()
            replayNativeRawInputMirrorIfNeeded(into: session)
            if var replayedSnapshot = nativeSession?.snapshot() {
                if !replayedSnapshot.rawInput.isEmpty {
                    nativeRawInputMirror = replayedSnapshot.rawInput
                } else if replayedSnapshot.hasComposition, !nativeRawInputMirror.isEmpty {
                    replayedSnapshot.rawInput = nativeRawInputMirror
                }
                currentSnapshot = replayedSnapshot
            }
            success = true
            details = "schema=\(configuredSchemaID) success=true"
        case .preemptedBySpeculativePrewarm:
            success = false
            details = "schema=\(configuredSchemaID) success=false reason=prewarm_busy"
        case .failed:
            nativeSessionCreationAttempted = true
            success = false
            details = "schema=\(configuredSchemaID) success=false"
        }
        Self.traceStartupEvent(
            "first_rime_session_create",
            elapsed: Date().timeIntervalSince(startedAt),
            details: details
        )
        guard success else {
            return nil
        }
        return nativeSession
    }

    private mutating func synchronizeNativeInputModeIfNeeded() {
        guard appliedNativeInputModeSnapshot != desiredInputModeSnapshot,
              let nativeSession,
              nativeSession.synchronizeInputMode(desiredInputModeSnapshot.state) else {
            return
        }
        appliedNativeInputModeSnapshot = desiredInputModeSnapshot
    }

    func nativeOptionValue(_ name: String) -> Bool? {
        nativeSession?.optionValue(name)
    }

    private static func shouldPreemptSpeculativePrewarm(
        for key: ConversionEngineKey,
        rawInput: String
    ) -> Bool {
        switch key {
        case .text,
             .deleteBackward:
            return true
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            return rawInput.isEmpty
        }
    }

    private mutating func replayNativeRawInputMirrorIfNeeded(into nativeSession: NativeRimeSession) {
        guard !nativeRawInputMirror.isEmpty else {
            return
        }
        for scalar in nativeRawInputMirror.unicodeScalars where Self.isPrintableASCIIScalar(scalar) {
            _ = nativeSession.process(.text(String(scalar)))
        }
    }

    private static func isPrintableASCIIScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x20...0x7e).contains(scalar.value)
    }

    private static func traceStartupEvent(_ event: String, elapsed: TimeInterval, details: String = "") {
        guard InputDebugDiagnostics.isEnabled(.startup) else {
            return
        }
        var fields: [InputDebugDiagnostics.Field] = [
            .init(.stage, event),
            .init(.elapsedMs, String(format: "%.1f", elapsed * 1_000))
        ]
        if !details.isEmpty {
            fields.append(.init(.reason, details))
        }
        InputDebugDiagnostics.emit(category: .startup, fields: fields)
    }

    private static func traceStartupEvent(_ event: String, details: String = "") {
        guard InputDebugDiagnostics.isEnabled(.startup) else {
            return
        }
        var fields: [InputDebugDiagnostics.Field] = [
            .init(.stage, event)
        ]
        if !details.isEmpty {
            fields.append(.init(.reason, details))
        }
        InputDebugDiagnostics.emit(category: .startup, fields: fields)
    }

    private static func traceProcess(
        key: ConversionEngineKey,
        result: ConversionEngineResult,
        elapsedMilliseconds: Double
    ) {
        InputDebugDiagnostics.emit(
            category: .rime,
            fields: [
                .init(.stage, "native_rime_process"),
                .init(.elapsedMs, String(format: "%.2f", elapsedMilliseconds)),
                .init(.reason, "key=\(key.privacySafeName);engine=\(result.snapshot.engineName)"),
                .init(.rawLength, result.snapshot.rawInput.count),
                .init(.handled, result.handled)
            ]
        )
    }

    private mutating func processRawBypass(_ key: ConversionEngineKey) -> ConversionEngineResult {
        let existingComposition = rawMirrorOrSnapshotInput()
        nativeBypassUntilReset = true
        nativeSession?.reset()
        nativeRawInputMirror = existingComposition
        return processUnavailable(key, engineName: "rime-raw-bypass")
    }

    private mutating func processUnavailable(
        _ key: ConversionEngineKey,
        engineName: String = "rime-unavailable"
    ) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            nativeRawInputMirror += text
            currentSnapshot = Self.unavailableSnapshot(rawInput: nativeRawInputMirror, engineName: engineName)
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .deleteBackward:
            if !nativeRawInputMirror.isEmpty {
                nativeRawInputMirror.removeLast()
            }
            currentSnapshot = Self.unavailableSnapshot(rawInput: nativeRawInputMirror, engineName: engineName)
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            currentSnapshot = Self.unavailableSnapshot(rawInput: nativeRawInputMirror, engineName: engineName)
            return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
        }
    }

    private func rawMirrorOrSnapshotInput() -> String {
        if !nativeRawInputMirror.isEmpty {
            return nativeRawInputMirror
        }
        if !currentSnapshot.rawInput.isEmpty {
            return currentSnapshot.rawInput
        }
        return currentSnapshot.preedit
    }

    private static func unavailableSnapshot(
        rawInput: String,
        engineName: String = "rime-unavailable"
    ) -> ConversionEngineSnapshot {
        ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [],
            highlightedIndex: 0,
            pageSize: 0,
            pageNumber: 0,
            isLastPage: true,
            engineName: engineName
        )
    }

    private static func containsNonASCIIText(_ key: ConversionEngineKey) -> Bool {
        guard case .text(let text) = key else {
            return false
        }
        return text.unicodeScalars.contains { !$0.isASCII }
    }
}

private extension ConversionEngineKey {
    var privacySafeName: String {
        switch self {
        case .text:
            return "text"
        case .space:
            return "space"
        case .deleteBackward:
            return "deleteBackward"
        case .selectCandidateOnCurrentPage:
            return "selectCandidateOnCurrentPage"
        case .selectCandidate:
            return "selectCandidate"
        case .highlightCandidateOnCurrentPage:
            return "highlightCandidateOnCurrentPage"
        case .pageUp:
            return "pageUp"
        case .pageDown:
            return "pageDown"
        case .commitComposition:
            return "commitComposition"
        }
    }
}

enum NativeRawInputMirrorPolicy {
    static func updatedMirror(
        current: String,
        key: ConversionEngineKey,
        result: ConversionEngineResult
    ) -> String {
        if !result.snapshot.hasComposition {
            return ""
        }
        if !result.snapshot.rawInput.isEmpty {
            return result.snapshot.rawInput
        }
        guard result.handled else {
            return current
        }

        switch key {
        case .text(let text):
            return current + text
        case .deleteBackward:
            var updated = current
            if !updated.isEmpty {
                updated.removeLast()
            }
            return updated
        case .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown:
            return current
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .commitComposition:
            return result.snapshot.preedit
        }
    }
}

public struct NativeRimeConfiguration: Sendable, Equatable {
    public var libraryURL: URL
    public var sharedDataURL: URL
    public var userDataURL: URL
    public var logURL: URL
    public var distributionVersion: String
    public var appName: String
    public var schemaID: String

    public init(
        libraryURL: URL,
        sharedDataURL: URL,
        userDataURL: URL,
        logURL: URL,
        distributionVersion: String = "0",
        appName: String = "rime.knowtype",
        schemaID: String = "pinyin_simp"
    ) {
        self.libraryURL = libraryURL
        self.sharedDataURL = sharedDataURL
        self.userDataURL = userDataURL
        self.logURL = logURL
        self.distributionVersion = distributionVersion
        self.appName = appName
        self.schemaID = schemaID
    }

    public static func defaultConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> NativeRimeConfiguration? {
        if environment["KNOWTYPE_RIME_ENABLED"] == "0" {
            return nil
        }
        let explicitLibraryPath = environment["KNOWTYPE_RIME_LIBRARY_PATH"]
        let explicitSharedDataPath = environment["KNOWTYPE_RIME_SHARED_DATA_DIR"]
        let enableSourceTreeArtifacts = environment["KNOWTYPE_RIME_ENABLED"] == "1"
        guard let libraryURL = firstExistingURL(
            environmentValue: explicitLibraryPath,
            candidates: defaultLibraryCandidates(
                includeSourceTreeArtifacts: enableSourceTreeArtifacts,
                fileManager: fileManager
            ),
            fileManager: fileManager
        ),
            let sharedDataURL = firstExistingURL(
                environmentValue: explicitSharedDataPath,
                candidates: defaultSharedDataCandidates(
                    includeSourceTreeArtifacts: enableSourceTreeArtifacts,
                    fileManager: fileManager
                ),
                fileManager: fileManager
            ) else {
            return nil
        }

        let supportDirectory = applicationSupportDirectory(environment: environment, fileManager: fileManager)
        let userDataURL = environment["KNOWTYPE_RIME_USER_DATA_DIR"].map {
            environmentFileURL(path: $0, isDirectory: true)
        }
            ?? supportDirectory.appendingPathComponent("Rime", isDirectory: true)
        let logURL = environment["KNOWTYPE_RIME_LOG_DIR"].map {
            environmentFileURL(path: $0, isDirectory: true)
        }
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/KnowType/Rime", isDirectory: true)
        return NativeRimeConfiguration(
            libraryURL: libraryURL,
            sharedDataURL: sharedDataURL,
            userDataURL: userDataURL,
            logURL: logURL,
            distributionVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            appName: "rime.knowtype",
            schemaID: environment["KNOWTYPE_RIME_SCHEMA_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "pinyin_simp"
        )
    }

    private static func firstExistingURL(
        environmentValue: String?,
        candidates: [URL],
        fileManager: FileManager
    ) -> URL? {
        if let environmentValue, !environmentValue.isEmpty {
            let url = environmentFileURL(path: environmentValue)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func environmentFileURL(path: String, isDirectory: Bool = false) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: isDirectory)
    }

    private static func defaultLibraryCandidates(
        includeSourceTreeArtifacts: Bool,
        fileManager: FileManager
    ) -> [URL] {
        var urls: [URL] = []
        if let frameworksPath = Bundle.main.privateFrameworksPath {
            let frameworksURL = URL(fileURLWithPath: frameworksPath, isDirectory: true)
            urls.append(frameworksURL.appendingPathComponent("librime.1.dylib"))
            urls.append(frameworksURL.appendingPathComponent("librime.1.16.1.dylib"))
        }
        if includeSourceTreeArtifacts {
            let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            urls.append(currentDirectory.appendingPathComponent("Vendor/Rime/dist/lib/librime.1.dylib"))
            urls.append(currentDirectory.appendingPathComponent("Vendor/Rime/dist/lib/librime.1.16.1.dylib"))
        }
        urls.append(URL(fileURLWithPath: "/opt/homebrew/opt/librime/lib/librime.1.dylib"))
        urls.append(URL(fileURLWithPath: "/usr/local/opt/librime/lib/librime.1.dylib"))
        return urls
    }

    private static func defaultSharedDataCandidates(
        includeSourceTreeArtifacts: Bool,
        fileManager: FileManager
    ) -> [URL] {
        var urls: [URL] = []
        if let resourcePath = Bundle.main.resourcePath {
            let resourceURL = URL(fileURLWithPath: resourcePath, isDirectory: true)
            urls.append(resourceURL.appendingPathComponent("rime-data", isDirectory: true))
            urls.append(resourceURL.appendingPathComponent("Rime", isDirectory: true))
        }
        if includeSourceTreeArtifacts {
            let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            urls.append(currentDirectory.appendingPathComponent("Vendor/Rime/share", isDirectory: true))
            urls.append(currentDirectory.appendingPathComponent("Vendor/Rime/data", isDirectory: true))
        }
        return urls
    }

    private static func applicationSupportDirectory(
        environment: [String: String],
        fileManager: FileManager
    ) -> URL {
        if isXCTestEnvironment(environment) {
            return fileManager.temporaryDirectory
                .appendingPathComponent("KnowTypeRimeXCTest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        if let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return directory.appendingPathComponent("KnowType", isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".knowtype", isDirectory: true)
    }

    private static func isXCTestEnvironment(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || ProcessInfo.processInfo.processName.contains(".xctest")
            || Bundle.main.bundlePath.contains(".xctest")
    }
}

protocol RimeUserDBSnapshotSession: Sendable {
    func userDataDirectory() -> URL?
    func userDataSyncDirectory() -> URL?
    func userDictionaryName(schemaID: String) -> String?
}

protocol RimeUserDBMaintenanceSession: RimeUserDBSnapshotSession {
    func syncUserData() -> Bool
}

final class NativeRimeSession: RimeUserDBMaintenanceSession, @unchecked Sendable {
    private enum CreationLockMode {
        case blocking
        case speculative
    }

    enum ForegroundCreationResult {
        case created(NativeRimeSession)
        case preemptedBySpeculativePrewarm
        case failed
    }

    private enum SessionCreationResult {
        case created(NativeRimeSession)
        case preemptedBySpeculativePrewarm
        case failed
    }

    private enum CreationSlotAcquireResult {
        case acquired
        case reusedPrewarmed(NativeRimeSession)
        case preemptedBySpeculativePrewarm
        case unavailable
    }

    private final class CreationState: @unchecked Sendable {
        let condition = NSCondition()
        var activeCreationMode: CreationLockMode?
        var foregroundCreationRequested = false
        var prewarmedSession: (configuration: NativeRimeConfiguration, session: NativeRimeSession)?
        var sessionCreateCalls = 0
        var prewarmCacheHits = 0
        var sessionPointerFactoryOverride: (@Sendable (NativeRimeConfiguration) -> OpaquePointer?)?
        var sessionPointerDestroyerOverride: (@Sendable (OpaquePointer) -> Void)?
    }

    private static let creationState = CreationState()

    private var session: OpaquePointer!
    private let sessionPointerDestroyer: (@Sendable (OpaquePointer) -> Void)?

    convenience init?(configuration: NativeRimeConfiguration, fileManager: FileManager = .default) {
        switch Self.makeSession(
            configuration: configuration,
            fileManager: fileManager,
            lockMode: .blocking,
            foregroundMayPreemptSpeculative: false
        ) {
        case .created(let createdSession):
            if let pointer = createdSession.detachSessionPointer() {
                self.init(session: pointer, sessionPointerDestroyer: createdSession.sessionPointerDestroyer)
            } else {
                return nil
            }
        case .preemptedBySpeculativePrewarm,
             .failed:
            return nil
        }
    }

    static func createForeground(
        configuration: NativeRimeConfiguration,
        fileManager: FileManager = .default,
        foregroundMayPreemptSpeculative: Bool = true
    ) -> ForegroundCreationResult {
        switch makeSession(
            configuration: configuration,
            fileManager: fileManager,
            lockMode: .blocking,
            foregroundMayPreemptSpeculative: foregroundMayPreemptSpeculative
        ) {
        case .created(let session):
            return .created(session)
        case .preemptedBySpeculativePrewarm:
            return .preemptedBySpeculativePrewarm
        case .failed:
            return .failed
        }
    }

    static func prewarm(
        configuration: NativeRimeConfiguration,
        fileManager: FileManager = .default
    ) -> NativeRimeSession? {
        switch makeSession(
            configuration: configuration,
            fileManager: fileManager,
            lockMode: .speculative,
            foregroundMayPreemptSpeculative: false
        ) {
        case .created(let session):
            return session
        case .preemptedBySpeculativePrewarm,
             .failed:
            return nil
        }
    }

    static func prewarmMetricsForTesting() -> (sessionCreateCalls: Int, prewarmCacheHits: Int, hasCachedSession: Bool) {
        creationState.condition.lock()
        defer {
            creationState.condition.unlock()
        }
        return (
            creationState.sessionCreateCalls,
            creationState.prewarmCacheHits,
            creationState.prewarmedSession != nil
        )
    }

    static func resetPrewarmStateForTesting() {
        var staleSession: NativeRimeSession?
        creationState.condition.lock()
        while creationState.activeCreationMode != nil {
            creationState.condition.wait()
        }
        staleSession = creationState.prewarmedSession?.session
        creationState.prewarmedSession = nil
        creationState.foregroundCreationRequested = false
        creationState.sessionCreateCalls = 0
        creationState.prewarmCacheHits = 0
        creationState.condition.unlock()
        _ = staleSession
    }

    static func withSessionPointerHooksForTesting<T>(
        create: @escaping @Sendable (NativeRimeConfiguration) -> OpaquePointer?,
        destroy: @escaping @Sendable (OpaquePointer) -> Void,
        body: () throws -> T
    ) rethrows -> T {
        resetPrewarmStateForTesting()
        creationState.condition.lock()
        creationState.sessionPointerFactoryOverride = create
        creationState.sessionPointerDestroyerOverride = destroy
        creationState.condition.unlock()
        defer {
            var staleSession: NativeRimeSession?
            creationState.condition.lock()
            while creationState.activeCreationMode != nil {
                creationState.condition.wait()
            }
            staleSession = creationState.prewarmedSession?.session
            creationState.prewarmedSession = nil
            creationState.foregroundCreationRequested = false
            creationState.sessionPointerFactoryOverride = nil
            creationState.sessionPointerDestroyerOverride = nil
            creationState.condition.unlock()
            _ = staleSession
        }
        return try body()
    }

    private init(
        session: OpaquePointer,
        sessionPointerDestroyer: (@Sendable (OpaquePointer) -> Void)? = nil
    ) {
        self.session = session
        self.sessionPointerDestroyer = sessionPointerDestroyer
    }

    private func detachSessionPointer() -> OpaquePointer? {
        guard let pointer = session else {
            return nil
        }
        session = nil
        return pointer
    }

    private static func makeSession(
        configuration: NativeRimeConfiguration,
        fileManager: FileManager,
        lockMode: CreationLockMode,
        foregroundMayPreemptSpeculative: Bool
    ) -> SessionCreationResult {
        if let cached = claimOrInspectPrewarmedSessionBeforeDirectorySetup(
            lockMode: lockMode,
            configuration: configuration
        ) {
            return .created(cached)
        }

        do {
            try fileManager.createDirectory(at: configuration.userDataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: configuration.logURL, withIntermediateDirectories: true)
        } catch {
            return .failed
        }

        switch acquireCreationSlot(
            lockMode,
            configuration: configuration,
            foregroundMayPreemptSpeculative: foregroundMayPreemptSpeculative
        ) {
        case .acquired:
            break
        case .reusedPrewarmed(let prewarmed):
            return .created(prewarmed)
        case .preemptedBySpeculativePrewarm:
            return .preemptedBySpeculativePrewarm
        case .unavailable:
            return .failed
        }

        var createdSessionForPrewarmCache: NativeRimeSession?
        var replacedPrewarmedSession: NativeRimeSession?
        defer {
            releaseCreationSlot(
                lockMode,
                configuration: configuration,
                createdPrewarmedSession: createdSessionForPrewarmCache,
                replacedPrewarmedSession: &replacedPrewarmedSession
            )
            _ = replacedPrewarmedSession
        }

        let (factoryOverride, destroyerOverride) = currentSessionPointerHooks()
        let pointer: OpaquePointer?
        if let factoryOverride {
            pointer = factoryOverride(configuration)
        } else {
            pointer = ktb_rime_session_create(
                configuration.libraryURL.path,
                configuration.sharedDataURL.path,
                configuration.userDataURL.path,
                configuration.logURL.path,
                configuration.distributionVersion,
                configuration.appName,
                configuration.schemaID
            )
        }
        guard let pointer else {
            return .failed
        }
        recordSessionCreated()
        let session = NativeRimeSession(
            session: pointer,
            sessionPointerDestroyer: destroyerOverride
        )
        if lockMode == .speculative {
            createdSessionForPrewarmCache = session
        }
        return .created(session)
    }

    private static func claimOrInspectPrewarmedSessionBeforeDirectorySetup(
        lockMode: CreationLockMode,
        configuration: NativeRimeConfiguration
    ) -> NativeRimeSession? {
        creationState.condition.lock()
        defer {
            creationState.condition.unlock()
        }
        switch lockMode {
        case .blocking:
            return takePrewarmedSessionLocked(matching: configuration)
        case .speculative:
            guard let cached = creationState.prewarmedSession,
                  cached.configuration == configuration else {
                return nil
            }
            return cached.session
        }
    }

    private static func currentSessionPointerHooks() -> (
        factory: (@Sendable (NativeRimeConfiguration) -> OpaquePointer?)?,
        destroyer: (@Sendable (OpaquePointer) -> Void)?
    ) {
        creationState.condition.lock()
        defer {
            creationState.condition.unlock()
        }
        return (
            creationState.sessionPointerFactoryOverride,
            creationState.sessionPointerDestroyerOverride
        )
    }

    private static func recordSessionCreated() {
        creationState.condition.lock()
        creationState.sessionCreateCalls += 1
        creationState.condition.unlock()
    }

    private static func acquireCreationSlot(
        _ mode: CreationLockMode,
        configuration: NativeRimeConfiguration,
        foregroundMayPreemptSpeculative: Bool
    ) -> CreationSlotAcquireResult {
        creationState.condition.lock()
        defer {
            creationState.condition.unlock()
        }

        switch mode {
        case .speculative:
            if let cached = creationState.prewarmedSession,
               cached.configuration == configuration {
                return .reusedPrewarmed(cached.session)
            }
            guard creationState.activeCreationMode == nil,
                  !creationState.foregroundCreationRequested else {
                return .unavailable
            }
            creationState.activeCreationMode = .speculative
            return .acquired
        case .blocking:
            if let prewarmed = takePrewarmedSessionLocked(matching: configuration) {
                return .reusedPrewarmed(prewarmed)
            }
            if foregroundMayPreemptSpeculative,
               creationState.activeCreationMode == .speculative {
                creationState.foregroundCreationRequested = true
                return .preemptedBySpeculativePrewarm
            }
            while creationState.activeCreationMode != nil {
                creationState.condition.wait()
            }
            if let prewarmed = takePrewarmedSessionLocked(matching: configuration) {
                return .reusedPrewarmed(prewarmed)
            }
            creationState.foregroundCreationRequested = false
            creationState.activeCreationMode = .blocking
            return .acquired
        }
    }

    private static func takePrewarmedSessionLocked(
        matching configuration: NativeRimeConfiguration
    ) -> NativeRimeSession? {
        guard let cached = creationState.prewarmedSession,
              cached.configuration == configuration else {
            return nil
        }
        creationState.prewarmedSession = nil
        creationState.foregroundCreationRequested = false
        creationState.prewarmCacheHits += 1
        return cached.session
    }

    private static func releaseCreationSlot(
        _ mode: CreationLockMode,
        configuration: NativeRimeConfiguration,
        createdPrewarmedSession: NativeRimeSession?,
        replacedPrewarmedSession: inout NativeRimeSession?
    ) {
        creationState.condition.lock()
        if mode == .speculative,
           let createdPrewarmedSession,
           creationState.prewarmedSession == nil || creationState.prewarmedSession?.configuration != configuration {
            replacedPrewarmedSession = creationState.prewarmedSession?.session
            creationState.prewarmedSession = (configuration, createdPrewarmedSession)
        }
        creationState.activeCreationMode = nil
        if mode == .blocking {
            creationState.foregroundCreationRequested = false
        }
        creationState.condition.broadcast()
        creationState.condition.unlock()
    }

    deinit {
        guard let session else {
            return
        }
        if let sessionPointerDestroyer {
            sessionPointerDestroyer(session)
        } else {
            ktb_rime_session_destroy(session)
        }
    }

    func reset() {
        ktb_rime_clear_composition(session)
    }

    func synchronizeInputMode(_ state: InputModeState) -> Bool {
        let options = RimeSessionModeOptions(state: state)
        var didApplyAllOptions = true
        for option in options.namedValues {
            if !setOption(option.name, value: option.value) {
                didApplyAllOptions = false
            }
        }
        return didApplyAllOptions
    }

    func setOption(_ name: String, value: Bool) -> Bool {
        name.withCString { ktb_rime_set_option(session, $0, value) }
    }

    func optionValue(_ name: String) -> Bool? {
        var value = false
        let didRead = name.withCString { ktb_rime_get_option(session, $0, &value) }
        return didRead ? value : nil
    }

    func snapshot() -> ConversionEngineSnapshot {
        guard let context = ktb_rime_copy_context(session) else {
            return ConversionEngineSnapshot(engineName: "rime-native")
        }
        defer {
            ktb_rime_context_snapshot_free(context)
        }

        let rawInput = context.pointee.raw_input.map { String(cString: $0) } ?? ""
        let preedit = context.pointee.preedit.map { String(cString: $0) } ?? ""
        let candidateCount = Int(context.pointee.candidate_count)
        var candidates: [ConversionEngineCandidate] = []
        if let candidatePointer = context.pointee.candidates {
            for index in 0..<candidateCount {
                let candidate = candidatePointer[index]
                let text = candidate.text.map { String(cString: $0) } ?? ""
                guard !text.isEmpty else {
                    continue
                }
                let comment = candidate.comment.map { String(cString: $0) }
                let nativeIndex = Int(candidate.index)
                candidates.append(
                    ConversionEngineCandidate(
                        text: text,
                        comment: comment?.isEmpty == true ? nil : comment,
                        index: nativeIndex >= 0 ? nativeIndex : index,
                        confidence: 1 - Double(index) * 0.01,
                        source: "rime-native"
                    )
                )
            }
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: preedit,
            candidates: candidates,
            highlightedIndex: Int(context.pointee.highlighted_candidate_index),
            pageSize: Int(context.pointee.page_size),
            pageNumber: Int(context.pointee.page_no),
            isLastPage: context.pointee.is_last_page,
            engineName: "rime-native"
        )
    }

    func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        let handled: Bool
        switch key {
        case .text(let text):
            handled = processText(text)
        case .space:
            handled = ktb_rime_process_key(session, 0x20, 0)
        case .deleteBackward:
            handled = ktb_rime_process_key(session, 0xff08, 0)
        case .selectCandidateOnCurrentPage(let index):
            handled = ktb_rime_select_candidate_on_current_page(session, max(0, index))
        case .selectCandidate(let index):
            handled = ktb_rime_select_candidate(session, max(0, index))
        case .highlightCandidateOnCurrentPage(let index):
            handled = ktb_rime_highlight_candidate_on_current_page(session, max(0, index))
        case .pageUp:
            handled = ktb_rime_change_page(session, true)
        case .pageDown:
            handled = ktb_rime_change_page(session, false)
        case .commitComposition:
            handled = ktb_rime_commit_composition(session)
        }
        let commitText = consumeCommit()
        let snapshot = snapshot()
        return ConversionEngineResult(
            handled: handled || commitText != nil,
            commitText: commitText,
            snapshot: snapshot
        )
    }

    private func processText(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
            return false
        }
        var handled = false
        for scalar in text.unicodeScalars {
            handled = ktb_rime_process_key(session, Int32(scalar.value), 0) || handled
        }
        return handled
    }

    private func consumeCommit() -> String? {
        guard let commit = ktb_rime_copy_commit(session) else {
            return nil
        }
        defer {
            ktb_rime_string_free(commit)
        }
        let text = String(cString: commit)
        return text.isEmpty ? nil : text
    }

    func syncUserData() -> Bool {
        ktb_rime_sync_user_data(session)
    }

    func userDataDirectory() -> URL? {
        guard let path = ktb_rime_copy_user_data_dir(session) else {
            return nil
        }
        defer {
            ktb_rime_string_free(path)
        }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    func userDataSyncDirectory() -> URL? {
        guard let path = ktb_rime_copy_user_data_sync_dir(session) else {
            return nil
        }
        defer {
            ktb_rime_string_free(path)
        }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    func currentSchemaID() -> String? {
        guard let schemaID = ktb_rime_copy_current_schema(session) else {
            return nil
        }
        defer {
            ktb_rime_string_free(schemaID)
        }
        let value = String(cString: schemaID).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func userDictionaryName(schemaID: String) -> String? {
        guard let name = schemaID.withCString({ ktb_rime_copy_schema_user_dict(session, $0) }) else {
            return nil
        }
        defer {
            ktb_rime_string_free(name)
        }
        let value = String(cString: name).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct RimeSessionModeOptions: Sendable, Equatable {
    var asciiMode: Bool
    var asciiPunct: Bool
    var fullShape: Bool

    init(state: InputModeState) {
        self.asciiMode = state.textMode == .ascii
        self.asciiPunct = state.punctuationMode == .english
        self.fullShape = state.symbolWidth == .fullWidth
    }

    var namedValues: [(name: String, value: Bool)] {
        [
            ("ascii_mode", asciiMode),
            ("ascii_punct", asciiPunct),
            ("full_shape", fullShape)
        ]
    }
}

public enum RimeUserDBTextSnapshotProviderError: Error, Equatable {
    case unavailable
    case syncFailed
    case snapshotNotFound(schemaID: String)
}

public actor RimeUserDBTextSnapshotProvider: RimeUserDBTextSnapshotSyncProviding {
    private let configuration: NativeRimeConfiguration?
    private let fileManager: FileManager
    private let locator: RimeUserDBSnapshotLocator
    private let customSessionFactory: (@Sendable (NativeRimeConfiguration) -> (any RimeUserDBSnapshotSession)?)?

    public init(
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.locator = RimeUserDBSnapshotLocator(fileManager: fileManager)
        self.customSessionFactory = nil
    }

    init(
        configuration: NativeRimeConfiguration?,
        fileManager: FileManager = .default,
        sessionFactory: @escaping @Sendable (NativeRimeConfiguration) -> (any RimeUserDBSnapshotSession)?
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.locator = RimeUserDBSnapshotLocator(fileManager: fileManager)
        self.customSessionFactory = sessionFactory
    }

    public func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        try await loadUserDBTextSnapshot(schemaID: schemaID, syncBeforeRead: false)
    }

    public func syncedUserDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        try await loadUserDBTextSnapshot(schemaID: schemaID, syncBeforeRead: true)
    }

    private func loadUserDBTextSnapshot(
        schemaID: String,
        syncBeforeRead: Bool
    ) async throws -> RimeUserDBTextSnapshot {
        guard let configuration else {
            throw RimeUserDBTextSnapshotProviderError.unavailable
        }
        let syncSucceeded: Bool
        let roots: [URL]
        let userDictionaryName: String
        if let customSessionFactory {
            guard let session = customSessionFactory(configuration) else {
                throw RimeUserDBTextSnapshotProviderError.unavailable
            }
            syncSucceeded = syncBeforeRead
                ? (session as? any RimeUserDBMaintenanceSession)?.syncUserData() ?? false
                : true
            roots = snapshotSearchRoots(
                syncDirectory: session.userDataSyncDirectory(),
                userDataDirectory: session.userDataDirectory() ?? configuration.userDataURL
            )
            userDictionaryName = session.userDictionaryName(schemaID: schemaID) ?? schemaID
        } else if syncBeforeRead {
            guard let session = NativeRimeSession(configuration: configuration, fileManager: fileManager) else {
                throw RimeUserDBTextSnapshotProviderError.unavailable
            }
            syncSucceeded = session.syncUserData()
            roots = snapshotSearchRoots(
                syncDirectory: session.userDataSyncDirectory(),
                userDataDirectory: session.userDataDirectory() ?? configuration.userDataURL
            )
            userDictionaryName = session.userDictionaryName(schemaID: schemaID) ?? schemaID
        } else {
            syncSucceeded = true
            let userDataDirectory = configuration.userDataURL
            let syncDirectory = locator.syncDirectory(in: userDataDirectory)
            roots = snapshotSearchRoots(
                syncDirectory: syncDirectory,
                userDataDirectory: userDataDirectory
            )
            userDictionaryName = locator.userDictionaryName(
                schemaID: schemaID,
                userDataDirectory: userDataDirectory,
                sharedDataDirectory: configuration.sharedDataURL
            ) ?? schemaID
        }
        guard let snapshotURL = locator.findUserDBTextSnapshot(userDBName: userDictionaryName, roots: roots) else {
            if !syncSucceeded {
                throw RimeUserDBTextSnapshotProviderError.syncFailed
            }
            throw RimeUserDBTextSnapshotProviderError.snapshotNotFound(schemaID: schemaID)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: snapshotURL.path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let content = try String(contentsOf: snapshotURL, encoding: .utf8)
        return RimeUserDBTextSnapshot(
            schemaID: schemaID,
            fileURL: snapshotURL,
            modifiedAt: modifiedAt,
            content: content
        )
    }

    private func snapshotSearchRoots(syncDirectory: URL?, userDataDirectory: URL) -> [URL] {
        locator.snapshotSearchRoots(syncDirectory: syncDirectory, userDataDirectory: userDataDirectory)
    }
}

struct RimeUserDBSnapshotLocator: @unchecked Sendable {
    var fileManager: FileManager

    func snapshotSearchRoots(syncDirectory: URL?, userDataDirectory: URL) -> [URL] {
        let installationID = installationID(in: userDataDirectory)
        let syncUnderUserData = userDataDirectory.appendingPathComponent("sync", isDirectory: true)
        var roots: [URL] = []
        if let syncDirectory, let installationID {
            roots.append(syncDirectory.appendingPathComponent(installationID, isDirectory: true))
        }
        if let installationID {
            roots.append(syncUnderUserData.appendingPathComponent(installationID, isDirectory: true))
        }
        if let syncDirectory {
            roots.append(syncDirectory)
        }
        roots.append(syncUnderUserData)
        roots.append(userDataDirectory)
        var seen = Set<String>()
        return roots.filter { root in
            let path = root.standardizedFileURL.path
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return fileManager.fileExists(atPath: path)
        }
    }

    func findUserDBTextSnapshot(userDBName: String, roots: [URL]) -> URL? {
        let filename = "\(userDBName).userdb.txt"
        var candidates: [SnapshotCandidate] = []
        var seen = Set<String>()
        for (rootIndex, root) in roots.enumerated() {
            let direct = root.appendingPathComponent(filename, isDirectory: false)
            if fileManager.fileExists(atPath: direct.path) {
                appendCandidate(direct, rootIndex: rootIndex, isDirect: true, candidates: &candidates, seen: &seen)
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator where url.lastPathComponent == filename {
                appendCandidate(url, rootIndex: rootIndex, isDirect: false, candidates: &candidates, seen: &seen)
            }
        }
        return candidates.sorted().first?.url
    }

    func installationID(in userDataDirectory: URL) -> String? {
        installationScalarValue(forKey: "installation_id", in: userDataDirectory)
    }

    func syncDirectory(in userDataDirectory: URL) -> URL? {
        guard let rawValue = installationScalarValue(forKey: "sync_dir", in: userDataDirectory) else {
            return nil
        }
        return NativeRimeConfiguration.environmentFileURL(path: rawValue, isDirectory: true)
    }

    func userDictionaryName(
        schemaID: String,
        userDataDirectory: URL,
        sharedDataDirectory: URL
    ) -> String? {
        guard !schemaID.isEmpty else {
            return nil
        }
        let candidates = [
            userDataDirectory.appendingPathComponent("build/\(schemaID).schema.yaml", isDirectory: false),
            userDataDirectory.appendingPathComponent("\(schemaID).schema.yaml", isDirectory: false),
            sharedDataDirectory.appendingPathComponent("build/\(schemaID).schema.yaml", isDirectory: false),
            sharedDataDirectory.appendingPathComponent("\(schemaID).schema.yaml", isDirectory: false)
        ]
        for candidateURL in candidates {
            guard let content = try? String(contentsOf: candidateURL, encoding: .utf8),
                  let dictName = Self.parseTranslatorDictionaryName(from: content) else {
                continue
            }
            return dictName
        }
        return nil
    }

    private func installationScalarValue(forKey key: String, in userDataDirectory: URL) -> String? {
        let installationURL = userDataDirectory.appendingPathComponent("installation.yaml", isDirectory: false)
        guard let content = try? String(contentsOf: installationURL, encoding: .utf8) else {
            return nil
        }
        let prefix = "\(key):"
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(prefix),
                  let separator = trimmed.firstIndex(of: ":") else {
                continue
            }
            let rawValue = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return rawValue.isEmpty ? nil : rawValue
        }
        return nil
    }

    private static func parseTranslatorDictionaryName(from content: String) -> String? {
        var inTranslatorSection = false
        var translatorIndent = 0
        var userDict: String?
        var dictionary: String?

        for line in content.split(whereSeparator: \.isNewline) {
            let uncommented = line.prefix { $0 != "#" }
            let trimmed = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let indent = uncommented.prefix { $0 == " " || $0 == "\t" }.count
            if !inTranslatorSection {
                if indent == 0, trimmed == "translator:" {
                    inTranslatorSection = true
                    translatorIndent = indent
                }
                continue
            }
            if indent <= translatorIndent {
                break
            }
            guard let separator = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else {
                continue
            }
            if key == "user_dict" {
                userDict = value
            } else if key == "dictionary" {
                dictionary = value
            }
        }
        return userDict ?? dictionary
    }

    private func appendCandidate(
        _ url: URL,
        rootIndex: Int,
        isDirect: Bool,
        candidates: inout [SnapshotCandidate],
        seen: inout Set<String>
    ) {
        let standardizedURL = url.standardizedFileURL
        guard !seen.contains(standardizedURL.path) else {
            return
        }
        seen.insert(standardizedURL.path)
        let modifiedAt = (try? standardizedURL.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)
        candidates.append(
            SnapshotCandidate(
                url: standardizedURL,
                rootIndex: rootIndex,
                isDirect: isDirect,
                modifiedAt: modifiedAt
            )
        )
    }

    private struct SnapshotCandidate: Comparable {
        var url: URL
        var rootIndex: Int
        var isDirect: Bool
        var modifiedAt: Date?

        static func < (lhs: SnapshotCandidate, rhs: SnapshotCandidate) -> Bool {
            if lhs.rootIndex != rhs.rootIndex {
                return lhs.rootIndex < rhs.rootIndex
            }
            if lhs.isDirect != rhs.isDirect {
                return lhs.isDirect && !rhs.isDirect
            }
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case (.some(let lhsDate), .some(let rhsDate)) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.url.path < rhs.url.path
            }
        }
    }
}

extension ConversionEngineSnapshot {
    func suggestionResponse(originalRawInput: String) -> SuggestionResponse? {
        guard !candidates.isEmpty else {
            return nil
        }
        let prefixCandidates = candidates.map { candidate in
            CorrectionCandidate(
                text: candidate.text,
                source: ConversionCandidateSource.encode(candidate.source, nativeIndex: candidate.index),
                confidence: candidate.confidence,
                correctionLevel: .contextual,
                protectedRanges: TextProtection.detectProtectedRanges(in: candidate.text),
                rawRange: TextRange(start: 0, length: originalRawInput.count)
            )
        }
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: nil,
            continuationCandidates: [],
            latencyMs: 0
        )
    }
}
