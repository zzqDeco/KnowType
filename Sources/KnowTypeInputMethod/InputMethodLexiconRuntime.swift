import Foundation
import KnowTypeCore

public struct InputMethodLexiconRuntimeSnapshot: Sendable, Equatable {
    public var directories: [InputMethodLexiconDirectorySnapshot]

    public init(directories: [InputMethodLexiconDirectorySnapshot]) {
        self.directories = directories
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

    public func makeEngine(fileManager: FileManager = .default) -> TraditionalInputEngine {
        loadCatalog(fileManager: fileManager).makeEngine()
    }

    public func snapshot(fileManager: FileManager = .default) -> InputMethodLexiconRuntimeSnapshot {
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
            }
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
        fileManager: FileManager = .default
    ) -> TraditionalInputEngine {
        defaultRuntime(
            environment: environment,
            homeDirectory: homeDirectory
        )
        .makeEngine(fileManager: fileManager)
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
                guard !file.lastPathComponent.hasPrefix("."),
                      TraditionalInputLexiconFileSource.format(for: file) != nil else {
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
