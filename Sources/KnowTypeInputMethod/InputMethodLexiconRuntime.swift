import Foundation
import KnowTypeCore

public struct InputMethodLexiconRuntime: Sendable, Equatable {
    public static let environmentDirectoryKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoryKey
    public static let environmentDirectoriesKey = TraditionalInputLexiconDirectoryResolver.environmentDirectoriesKey
    private static let cachedDefaultEngine = defaultRuntime().makeEngine()

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

    public static func defaultEngine() -> TraditionalInputEngine {
        cachedDefaultEngine
    }

    private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
