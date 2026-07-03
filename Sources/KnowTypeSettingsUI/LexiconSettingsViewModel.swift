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
    public var installedPacks: [InstalledLexiconPackStatus]
    public var diagnostics: [LexiconDiagnosticStatus]

    public init(
        directory: URL,
        exists: Bool,
        resourceFileCount: Int,
        loadedEntryCount: Int,
        installedPacks: [InstalledLexiconPackStatus] = [],
        diagnostics: [LexiconDiagnosticStatus]
    ) {
        self.directory = directory
        self.exists = exists
        self.resourceFileCount = resourceFileCount
        self.loadedEntryCount = loadedEntryCount
        self.installedPacks = installedPacks
        self.diagnostics = diagnostics
    }
}

public struct InstalledLexiconPackStatus: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var entryCount: Int
    public var licenseName: String
    public var licenseURL: URL
    public var sourceURL: URL
    public var installedAt: Date

    public init(metadata: InstalledLexiconPackMetadata) {
        self.id = metadata.id
        self.displayName = metadata.displayName
        self.entryCount = metadata.entryCount
        self.licenseName = metadata.licenseName
        self.licenseURL = metadata.licenseURL
        self.sourceURL = metadata.sourceURL
        self.installedAt = metadata.installedAt
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
    @Published public private(set) var isInstallingRecommendedPack: Bool

    private let directoryURLs: [URL]
    private let fileManager: FileManager
    private let fileSource: TraditionalInputLexiconFileSource
    private let dateProvider: () -> Date
    private let recommendedPackInstaller: (ManagedLexiconPack, URL, Bool) async throws -> InstalledLexiconPackMetadata

    public init(
        directoryURLs: [URL] = LexiconSettingsViewModel.defaultLexiconDirectories(),
        fileManager: FileManager = .default,
        fileSource: TraditionalInputLexiconFileSource = TraditionalInputLexiconFileSource(),
        dateProvider: @escaping () -> Date = Date.init,
        recommendedPackInstaller: @escaping (ManagedLexiconPack, URL, Bool) async throws -> InstalledLexiconPackMetadata = { pack, directory, force in
            try await ManagedLexiconPackInstaller().install(
                pack,
                destinationDirectory: directory,
                force: force
            )
        }
    ) {
        self.directoryURLs = TraditionalInputLexiconDirectoryResolver.uniqueDirectories(directoryURLs)
        self.fileManager = fileManager
        self.fileSource = fileSource
        self.dateProvider = dateProvider
        self.recommendedPackInstaller = recommendedPackInstaller
        self.directories = []
        self.totalLoadedEntryCount = 0
        self.lastActionMessage = nil
        self.isInstallingRecommendedPack = false
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
                ? SettingsLocalization.string("settings.lexicon.action.allDirectoriesExist")
                : String(
                    format: SettingsLocalization.string("settings.lexicon.action.createdDirectories"),
                    createdCount
                )
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
            lastActionMessage = SettingsLocalization.string("settings.lexicon.action.noDirectory")
            refresh()
            return false
        }

        do {
            if !isDirectory(directory) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let file = directory.appendingPathComponent(Self.sampleResourceFileName)
            guard !fileManager.fileExists(atPath: file.path) else {
                lastActionMessage = String(
                    format: SettingsLocalization.string("settings.lexicon.action.sampleExists"),
                    Self.sampleResourceFileName
                )
                refresh()
                return true
            }

            try Data(Self.sampleResourceContents.utf8).write(to: file, options: [.atomic])
            lastActionMessage = String(
                format: SettingsLocalization.string("settings.lexicon.action.sampleCreated"),
                Self.sampleResourceFileName
            )
            refresh()
            return true
        } catch {
            lastActionMessage = error.localizedDescription
            refresh()
            return false
        }
    }

    @discardableResult
    public func installRecommendedLexiconPack(force: Bool = false) async -> Bool {
        guard let directory = directoryURLs.first else {
            lastActionMessage = SettingsLocalization.string("settings.lexicon.action.noDirectory")
            refresh()
            return false
        }

        isInstallingRecommendedPack = true
        defer {
            isInstallingRecommendedPack = false
            refresh()
        }

        do {
            let metadata = try await recommendedPackInstaller(
                ManagedLexiconPacks.recommended,
                directory,
                force
            )
            lastActionMessage = String(
                format: SettingsLocalization.string("settings.lexicon.action.installedRecommended"),
                metadata.displayName,
                metadata.entryCount
            )
            return true
        } catch {
            lastActionMessage = error.localizedDescription
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
                installedPacks: [],
                diagnostics: []
            )
        }

        let catalog = fileSource.loadDirectory(directory)
        return LexiconDirectoryStatus(
            directory: directory,
            exists: true,
            resourceFileCount: resourceFileCount(in: directory),
            loadedEntryCount: catalog.entries.count,
            installedPacks: installedPackStatuses(in: directory),
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
            guard TraditionalInputLexiconFileSource.isLexiconResourceFile(url) else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory != true && values?.isHidden != true
        }.count
    }

    private func installedPackStatuses(in directory: URL) -> [InstalledLexiconPackStatus] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { url in
                guard url.lastPathComponent.hasSuffix(".metadata.json") else {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                return values?.isDirectory != true && values?.isHidden != true
            }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let metadata = try? decoder.decode(InstalledLexiconPackMetadata.self, from: data) else {
                    return nil
                }
                return InstalledLexiconPackStatus(metadata: metadata)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }
}
