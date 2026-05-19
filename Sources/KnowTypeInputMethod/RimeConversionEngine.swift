import Foundation
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

public struct ConversionEngineSnapshot: Sendable, Equatable {
    public var rawInput: String
    public var preedit: String
    public var candidates: [ConversionEngineCandidate]
    public var highlightedIndex: Int
    public var pageSize: Int
    public var pageNumber: Int
    public var isLastPage: Bool
    public var engineName: String

    public init(
        rawInput: String = "",
        preedit: String = "",
        candidates: [ConversionEngineCandidate] = [],
        highlightedIndex: Int = 0,
        pageSize: Int = 0,
        pageNumber: Int = 0,
        isLastPage: Bool = true,
        engineName: String = "traditional-fallback"
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
    case pageUp
    case pageDown
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

    mutating func reset()
    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult
}

public struct RimeConversionEngine: KnowTypeConversionEngine {
    private var fallback: TraditionalFallbackConversionEngine
    private var nativeSession: NativeRimeSession?
    private var currentSnapshot: ConversionEngineSnapshot

    public var isNativeActive: Bool {
        nativeSession != nil
    }

    public var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    public init(
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine(),
        configuration: NativeRimeConfiguration? = NativeRimeConfiguration.defaultConfiguration()
    ) {
        self.fallback = TraditionalFallbackConversionEngine(traditionalInputEngine: traditionalInputEngine)
        self.nativeSession = configuration.flatMap { NativeRimeSession(configuration: $0) }
        self.currentSnapshot = nativeSession?.snapshot() ?? fallback.snapshot
    }

    public mutating func reset() {
        nativeSession?.reset()
        fallback.reset()
        currentSnapshot = nativeSession?.snapshot() ?? fallback.snapshot
    }

    public mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        guard let nativeSession else {
            let result = fallback.process(key)
            currentSnapshot = result.snapshot
            return result
        }

        let result = nativeSession.process(key)
        currentSnapshot = result.snapshot
        if result.handled {
            return result
        }

        let fallbackResult = fallback.process(key)
        currentSnapshot = fallbackResult.snapshot
        return fallbackResult
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
                includeSourceTreeArtifacts: enableSourceTreeArtifacts || explicitLibraryPath != nil,
                fileManager: fileManager
            ),
            fileManager: fileManager
        ),
            let sharedDataURL = firstExistingURL(
                environmentValue: explicitSharedDataPath,
                candidates: defaultSharedDataCandidates(
                    includeSourceTreeArtifacts: enableSourceTreeArtifacts || explicitSharedDataPath != nil,
                    fileManager: fileManager
                ),
                fileManager: fileManager
            ) else {
            return nil
        }

        let supportDirectory = applicationSupportDirectory(fileManager: fileManager)
        let userDataURL = environment["KNOWTYPE_RIME_USER_DATA_DIR"].map(URL.init(fileURLWithPath:))
            ?? supportDirectory.appendingPathComponent("Rime", isDirectory: true)
        let logURL = environment["KNOWTYPE_RIME_LOG_DIR"].map(URL.init(fileURLWithPath:))
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/KnowType/Rime", isDirectory: true)
        return NativeRimeConfiguration(
            libraryURL: libraryURL,
            sharedDataURL: sharedDataURL,
            userDataURL: userDataURL,
            logURL: logURL,
            distributionVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            appName: "rime.knowtype"
        )
    }

    private static func firstExistingURL(
        environmentValue: String?,
        candidates: [URL],
        fileManager: FileManager
    ) -> URL? {
        if let environmentValue, !environmentValue.isEmpty {
            let url = URL(fileURLWithPath: environmentValue)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
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

    private static func applicationSupportDirectory(fileManager: FileManager) -> URL {
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
}

final class NativeRimeSession: @unchecked Sendable {
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

        let rawInput = ""
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
                candidates.append(
                    ConversionEngineCandidate(
                        text: text,
                        comment: comment?.isEmpty == true ? nil : comment,
                        index: index,
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
        case .pageUp:
            handled = ktb_rime_change_page(session, true)
        case .pageDown:
            handled = ktb_rime_change_page(session, false)
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
                continue
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
}

private struct TraditionalFallbackConversionEngine: KnowTypeConversionEngine {
    private var rawInput = ""
    private let traditionalInputEngine: TraditionalInputEngine

    var isNativeActive: Bool {
        false
    }

    var snapshot: ConversionEngineSnapshot {
        snapshot(for: rawInput)
    }

    init(traditionalInputEngine: TraditionalInputEngine) {
        self.traditionalInputEngine = traditionalInputEngine
    }

    mutating func reset() {
        rawInput = ""
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput.append(text)
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space:
            let commit = snapshot.candidates.first?.text ?? rawInput
            rawInput = ""
            return ConversionEngineResult(handled: !commit.isEmpty, commitText: commit.isEmpty ? nil : commit, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .selectCandidateOnCurrentPage(let index):
            let candidates = snapshot.candidates
            guard candidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            let commit = candidates[index].text
            rawInput = ""
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: snapshot)
        case .pageUp, .pageDown:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }

    private func snapshot(for rawInput: String) -> ConversionEngineSnapshot {
        guard !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ConversionEngineSnapshot(rawInput: rawInput)
        }
        let candidates = traditionalInputEngine
            .candidates(
                for: rawInput,
                options: InputMethodPipeline.interactiveQueryOptions
            )
            .enumerated()
            .map { index, candidate in
                ConversionEngineCandidate(
                    text: candidate.text,
                    index: index,
                    confidence: candidate.confidence,
                    source: "traditional-fallback"
                )
            }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: candidates,
            highlightedIndex: 0,
            pageSize: min(max(candidates.count, 1), InputMethodRuntimePreferences.adaptiveCandidatePageSize),
            pageNumber: 0,
            isLastPage: true,
            engineName: "traditional-fallback"
        )
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
                source: candidate.source,
                confidence: candidate.confidence,
                correctionLevel: .contextual,
                protectedRanges: TextProtection.detectProtectedRanges(in: candidate.text),
                rawRange: TextRange(start: 0, length: originalRawInput.count)
            )
        }
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: prefixCandidates.first.map {
                LockedPrefix(text: $0.text, rawInput: originalRawInput, candidateID: $0.source)
            },
            continuationCandidates: [],
            latencyMs: 0
        )
    }
}
