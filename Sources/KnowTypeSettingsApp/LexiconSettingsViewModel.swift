import Combine
import Foundation
import KnowTypeCore

public struct LexiconDiagnosticStatus: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(resourceID):\(message)"
    }

    public var resourceID: String
    public var message: String

    public init(resourceID: String, message: String) {
        self.resourceID = resourceID
        self.message = message
    }
}

public struct LexiconDirectoryStatus: Sendable, Equatable, Identifiable {
    public var id: String {
        directory.standardizedFileURL.path
    }

    public var directory: URL
    public var exists: Bool
    public var resourceFileCount: Int
    public var loadedEntryCount: Int
    public var diagnostics: [LexiconDiagnosticStatus]

    public init(
        directory: URL,
        exists: Bool,
        resourceFileCount: Int,
        loadedEntryCount: Int,
        diagnostics: [LexiconDiagnosticStatus]
    ) {
        self.directory = directory
        self.exists = exists
        self.resourceFileCount = resourceFileCount
        self.loadedEntryCount = loadedEntryCount
        self.diagnostics = diagnostics
    }
}

@MainActor
public final class LexiconSettingsViewModel: ObservableObject {
    public static let environmentDirectoryKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoryKey
    public static let environmentDirectoriesKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoriesKey
    public static let sampleResourceFileName = "knowtype-sample.tsv"
    public static let sampleResourceContents = """
    # pinyin<TAB>text<TAB>confidence
    zi zao ci\t自造词\t0.995
    ce shi ci\t测试词\t0.990
    """

    @Published public private(set) var directories: [LexiconDirectoryStatus]
    @Published public private(set) var totalLoadedEntryCount: Int
    @Published public private(set) var lastRefreshDate: Date?
    @Published public private(set) var lastActionMessage: String?

    private let directoryURLs: [URL]
    private let fileManager: FileManager
    private let fileSource: TraditionalInputLexiconFileSource
    private let dateProvider: () -> Date

    public init(
        directoryURLs: [URL] = LexiconSettingsViewModel.defaultLexiconDirectories(),
        fileManager: FileManager = .default,
        fileSource: TraditionalInputLexiconFileSource = TraditionalInputLexiconFileSource(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.directoryURLs = TraditionalInputLexiconDirectoryResolver.uniqueDirectories(directoryURLs)
        self.fileManager = fileManager
        self.fileSource = fileSource
        self.dateProvider = dateProvider
        self.directories = []
        self.totalLoadedEntryCount = 0
        self.lastActionMessage = nil
        refresh()
    }

    public static func defaultLexiconDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        TraditionalInputLexiconDirectoryResolver.defaultDirectories(
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    public func refresh() {
        let snapshots = directoryURLs.map(loadDirectoryStatus)
        directories = snapshots
        totalLoadedEntryCount = snapshots.reduce(0) { total, snapshot in
            total + snapshot.loadedEntryCount
        }
        lastRefreshDate = dateProvider()
    }

    @discardableResult
    public func createMissingDirectories() -> Bool {
        var createdCount = 0
        do {
            for directory in directoryURLs where !isDirectory(directory) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                createdCount += 1
            }
            lastActionMessage = createdCount == 0
                ? "All lexicon directories already exist."
                : "Created \(createdCount) lexicon director\(createdCount == 1 ? "y" : "ies")."
            refresh()
            return true
        } catch {
            lastActionMessage = error.localizedDescription
            refresh()
            return false
        }
    }

    @discardableResult
    public func createSampleLexiconResource() -> Bool {
        guard let directory = directoryURLs.first else {
            lastActionMessage = "No lexicon directory is configured."
            refresh()
            return false
        }

        do {
            if !isDirectory(directory) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let file = directory.appendingPathComponent(Self.sampleResourceFileName)
            guard !fileManager.fileExists(atPath: file.path) else {
                lastActionMessage = "\(Self.sampleResourceFileName) already exists."
                refresh()
                return true
            }

            try Data(Self.sampleResourceContents.utf8).write(to: file, options: [.atomic])
            lastActionMessage = "Created \(Self.sampleResourceFileName)."
            refresh()
            return true
        } catch {
            lastActionMessage = error.localizedDescription
            refresh()
            return false
        }
    }

    private func loadDirectoryStatus(_ directory: URL) -> LexiconDirectoryStatus {
        guard isDirectory(directory) else {
            return LexiconDirectoryStatus(
                directory: directory,
                exists: false,
                resourceFileCount: 0,
                loadedEntryCount: 0,
                diagnostics: []
            )
        }

        let catalog = fileSource.loadDirectory(directory)
        return LexiconDirectoryStatus(
            directory: directory,
            exists: true,
            resourceFileCount: resourceFileCount(in: directory),
            loadedEntryCount: catalog.entries.count,
            diagnostics: catalog.diagnostics.map { diagnostic in
                LexiconDiagnosticStatus(
                    resourceID: diagnostic.resourceID,
                    message: diagnostic.error.localizedDescription
                )
            }
        )
    }

    private func isDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func resourceFileCount(in directory: URL) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        return files.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  TraditionalInputLexiconFileSource.format(for: url) != nil else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory != true && values?.isHidden != true
        }.count
    }

}
