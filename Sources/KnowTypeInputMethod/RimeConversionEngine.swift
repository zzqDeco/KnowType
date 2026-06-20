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

    mutating func reset()
    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult
}

public extension KnowTypeConversionEngine {
    var activeSchemaID: String {
        "pinyin_simp"
    }

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
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration()
    ) {
        self.nativeConfiguration = configuration
        self.configuredSchemaID = configuration?.schemaID ?? "pinyin_simp"
        self.nativeSession = nil
        self.currentSnapshot = Self.unavailableSnapshot(rawInput: "")
    }

    public mutating func reset() {
        nativeBypassUntilReset = false
        nativeRawInputMirror = ""
        nativeSession?.reset()
        currentSnapshot = nativeSession?.snapshot() ?? Self.unavailableSnapshot(rawInput: "")
    }

    public mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        if Self.containsNonASCIIText(key) {
            return processRawBypass(key)
        }

        guard !nativeBypassUntilReset else {
            return processUnavailable(key, engineName: "rime-raw-bypass")
        }

        let nativeSession = ensureNativeSession()
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

    private mutating func ensureNativeSession() -> NativeRimeSession? {
        if let nativeSession {
            return nativeSession
        }
        guard !nativeSessionCreationAttempted,
              let nativeConfiguration else {
            return nil
        }
        nativeSessionCreationAttempted = true
        nativeSession = NativeRimeSession(configuration: nativeConfiguration)
        currentSnapshot = nativeSession?.snapshot() ?? currentSnapshot
        return nativeSession
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

enum NativeRawInputMirrorPolicy {
    static func updatedMirror(
        current: String,
        key: ConversionEngineKey,
        result: ConversionEngineResult
    ) -> String {
        guard result.handled else {
            return current
        }
        if !result.snapshot.rawInput.isEmpty || !result.snapshot.hasComposition {
            return result.snapshot.rawInput
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
    private let session: OpaquePointer

    init?(configuration: NativeRimeConfiguration, fileManager: FileManager = .default) {
        do {
            try fileManager.createDirectory(at: configuration.userDataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: configuration.logURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        guard let session = ktb_rime_session_create(
            configuration.libraryURL.path,
            configuration.sharedDataURL.path,
            configuration.userDataURL.path,
            configuration.logURL.path,
            configuration.distributionVersion,
            configuration.appName,
            configuration.schemaID
        ) else {
            return nil
        }
        self.session = session
    }

    deinit {
        ktb_rime_session_destroy(session)
    }

    func reset() {
        ktb_rime_clear_composition(session)
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
        var handled = false
        for scalar in text.unicodeScalars {
            guard scalar.isASCII else {
                return false
            }
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

public enum RimeUserDBTextSnapshotProviderError: Error, Equatable {
    case unavailable
    case syncFailed
    case snapshotNotFound(schemaID: String)
}

public actor RimeUserDBTextSnapshotProvider: RimeUserDBTextSnapshotSyncProviding {
    private let configuration: NativeRimeConfiguration?
    private let fileManager: FileManager
    private let locator: RimeUserDBSnapshotLocator
    private let sessionFactory: @Sendable (NativeRimeConfiguration) -> (any RimeUserDBSnapshotSession)?

    public init(
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.init(
            configuration: configuration,
            fileManager: fileManager,
            sessionFactory: { NativeRimeSession(configuration: $0) }
        )
    }

    init(
        configuration: NativeRimeConfiguration?,
        fileManager: FileManager = .default,
        sessionFactory: @escaping @Sendable (NativeRimeConfiguration) -> (any RimeUserDBSnapshotSession)?
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.locator = RimeUserDBSnapshotLocator(fileManager: fileManager)
        self.sessionFactory = sessionFactory
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
        guard let configuration,
              let session = sessionFactory(configuration) else {
            throw RimeUserDBTextSnapshotProviderError.unavailable
        }
        let syncSucceeded = syncBeforeRead
            ? (session as? any RimeUserDBMaintenanceSession)?.syncUserData() ?? false
            : true
        let roots = snapshotSearchRoots(
            syncDirectory: session.userDataSyncDirectory(),
            userDataDirectory: session.userDataDirectory() ?? configuration.userDataURL
        )
        let userDictionaryName = session.userDictionaryName(schemaID: schemaID) ?? schemaID
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
        let installationURL = userDataDirectory.appendingPathComponent("installation.yaml", isDirectory: false)
        guard let content = try? String(contentsOf: installationURL, encoding: .utf8) else {
            return nil
        }
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("installation_id:"),
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
