import Foundation
import KnowTypeCore

public struct InputMethodLexiconRuntimeSnapshot: Sendable, Equatable {
    public var directories: [InputMethodLexiconDirectorySnapshot]
    public var scheme: TraditionalInputEngine.Scheme

    public init(
        directories: [InputMethodLexiconDirectorySnapshot],
        scheme: TraditionalInputEngine.Scheme = .fullPinyin
    ) {
        self.directories = directories
        self.scheme = scheme
    }

    public var hasLexiconResources: Bool {
        directories.contains { !$0.resources.isEmpty }
    }
}

public struct InputMethodLexiconRuntimeEngineState: Sendable {
    public var engine: TraditionalInputEngine
    public var snapshot: InputMethodLexiconRuntimeSnapshot

    public init(engine: TraditionalInputEngine, snapshot: InputMethodLexiconRuntimeSnapshot) {
        self.engine = engine
        self.snapshot = snapshot
    }
}

public struct InputMethodLexiconDirectorySnapshot: Sendable, Equatable {
    public var directory: URL
    public var exists: Bool
    public var resources: [InputMethodLexiconResourceSnapshot]

    public init(directory: URL, exists: Bool, resources: [InputMethodLexiconResourceSnapshot]) {
        self.directory = directory
        self.exists = exists
        self.resources = resources
    }
}

public struct InputMethodLexiconResourceSnapshot: Sendable, Equatable {
    public var file: URL
    public var modificationDate: Date?
    public var fileSize: Int64?

    public init(file: URL, modificationDate: Date?, fileSize: Int64?) {
        self.file = file
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }
}

public struct InputMethodLexiconRuntime: Sendable, Equatable {
    public static let environmentDirectoryKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoryKey
    public static let environmentDirectoriesKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoriesKey

    public var directories: [URL]

    public init(directories: [URL]) {
        self.directories = directories
    }

    public static func defaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> InputMethodLexiconRuntime {
        InputMethodLexiconRuntime(
            directories: defaultDirectories(
                environment: environment,
                homeDirectory: homeDirectory
            )
        )
    }

    public static func defaultDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        TraditionalInputLexiconDirectoryResolver.defaultDirectories(
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    public func loadCatalog(fileManager: FileManager = .default) -> TraditionalInputLexiconCatalog {
        let fileSource = TraditionalInputLexiconFileSource()
        var entries: [TraditionalInputLexiconEntry] = []
        var diagnostics: [TraditionalInputLexiconDiagnostic] = []

        for directory in directories where isDirectory(directory, fileManager: fileManager) {
            let catalog = fileSource.loadDirectory(directory)
            entries.append(contentsOf: catalog.entries)
            diagnostics.append(contentsOf: catalog.diagnostics)
        }

        return TraditionalInputLexiconCatalog(entries: entries, diagnostics: diagnostics)
    }

    public func makeEngine(
        scheme: TraditionalInputEngine.Scheme = .fullPinyin,
        fileManager: FileManager = .default
    ) -> TraditionalInputEngine {
        loadCatalog(fileManager: fileManager).makeEngine(scheme: scheme)
    }

    public func initialEngineState(
        scheme: TraditionalInputEngine.Scheme = .fullPinyin,
        fileManager: FileManager = .default
    ) -> InputMethodLexiconRuntimeEngineState {
        let snapshot = snapshot(scheme: scheme, fileManager: fileManager)
        if let cachedEngine = InputMethodLexiconRuntimeEngineCache.shared.engine(for: snapshot) {
            return InputMethodLexiconRuntimeEngineState(engine: cachedEngine, snapshot: snapshot)
        }
        guard snapshot.hasLexiconResources else {
            let engine = TraditionalInputEngine(scheme: scheme)
            InputMethodLexiconRuntimeEngineCache.shared.store(engine: engine, snapshot: snapshot)
            return InputMethodLexiconRuntimeEngineState(engine: engine, snapshot: snapshot)
        }

        let engine = makeEngine(scheme: scheme, fileManager: fileManager)
        InputMethodLexiconRuntimeEngineCache.shared.store(engine: engine, snapshot: snapshot)
        return InputMethodLexiconRuntimeEngineState(engine: engine, snapshot: snapshot)
    }

    public func snapshot(
        scheme: TraditionalInputEngine.Scheme = .fullPinyin,
        fileManager: FileManager = .default
    ) -> InputMethodLexiconRuntimeSnapshot {
        InputMethodLexiconRuntimeSnapshot(
            directories: directories.map { directory in
                guard isDirectory(directory, fileManager: fileManager) else {
                    return InputMethodLexiconDirectorySnapshot(
                        directory: directory.standardizedFileURL,
                        exists: false,
                        resources: []
                    )
                }

                return InputMethodLexiconDirectorySnapshot(
                    directory: directory.standardizedFileURL,
                    exists: true,
                    resources: resourceFiles(in: directory, fileManager: fileManager).map { file in
                        resourceSnapshot(for: file)
                    }
                )
            },
            scheme: scheme
        )
    }

    public static func defaultEngine() -> TraditionalInputEngine {
        defaultEngine(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    public static func defaultEngine(
        environment: [String: String],
        homeDirectory: URL,
        scheme: TraditionalInputEngine.Scheme = .fullPinyin,
        fileManager: FileManager = .default
    ) -> TraditionalInputEngine {
        defaultRuntime(
            environment: environment,
            homeDirectory: homeDirectory
        )
        .makeEngine(scheme: scheme, fileManager: fileManager)
    }

    public static func prewarmDefaultEngine(scheme: TraditionalInputEngine.Scheme = .fullPinyin) {
        let runtime = defaultRuntime()
        let snapshot = runtime.snapshot(scheme: scheme)
        guard snapshot.hasLexiconResources,
              InputMethodLexiconRuntimeEngineCache.shared.engine(for: snapshot) == nil else {
            return
        }
        let engine = runtime.makeEngine(scheme: scheme)
        InputMethodLexiconRuntimeEngineCache.shared.store(engine: engine, snapshot: snapshot)
    }

    public static func cacheEngine(_ engine: TraditionalInputEngine, snapshot: InputMethodLexiconRuntimeSnapshot) {
        InputMethodLexiconRuntimeEngineCache.shared.store(engine: engine, snapshot: snapshot)
    }

    private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func resourceFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        return files
            .filter { file in
                guard TraditionalInputLexiconFileSource.isLexiconResourceFile(file) else {
                    return false
                }
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                return values?.isDirectory != true && values?.isHidden != true
            }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    private func resourceSnapshot(for file: URL) -> InputMethodLexiconResourceSnapshot {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return InputMethodLexiconResourceSnapshot(
            file: file.standardizedFileURL,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize.map(Int64.init)
        )
    }
}

private final class InputMethodLexiconRuntimeEngineCache: @unchecked Sendable {
    static let shared = InputMethodLexiconRuntimeEngineCache()

    private let lock = NSLock()
    private var snapshot: InputMethodLexiconRuntimeSnapshot?
    private var engine: TraditionalInputEngine?

    func engine(for snapshot: InputMethodLexiconRuntimeSnapshot) -> TraditionalInputEngine? {
        lock.lock()
        defer { lock.unlock() }
        guard self.snapshot == snapshot else {
            return nil
        }
        return engine
    }

    func store(engine: TraditionalInputEngine, snapshot: InputMethodLexiconRuntimeSnapshot) {
        lock.lock()
        self.engine = engine
        self.snapshot = snapshot
        lock.unlock()
    }
}
