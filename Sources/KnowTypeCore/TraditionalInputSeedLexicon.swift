import Foundation

public enum TraditionalInputSeedLexicon {
    public static let resourceID = "seed.tsv"

    private static let cachedCatalog = loadCatalog()

    public static func catalog() -> TraditionalInputLexiconCatalog {
        cachedCatalog
    }

    public static func entries() -> [TraditionalInputLexiconEntry] {
        cachedCatalog.entries
    }

    private static func loadCatalog() -> TraditionalInputLexiconCatalog {
        guard let url = seedResourceURL() else {
            return TraditionalInputLexiconCatalog(
                entries: [],
                diagnostics: [
                    TraditionalInputLexiconDiagnostic(
                        resourceID: resourceID,
                        error: .unreadableResource("Bundled seed lexicon resource is missing.")
                    )
                ]
            )
        }

        return TraditionalInputLexiconFileSource().loadFiles([url])
    }

    private static func seedResourceURL() -> URL? {
        if let packagedURL = packagedSeedResourceURL() {
            return packagedURL
        }

        #if SWIFT_PACKAGE
        if isSwiftPMBuildOrTestProcess {
            return Bundle.module.url(forResource: "seed", withExtension: "tsv")
        }
        #endif

        return nil
    }

    private static func packagedSeedResourceURL() -> URL? {
        candidateBundleURLs().lazy
            .map { $0.appendingPathComponent("seed.tsv") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func candidateBundleURLs() -> [URL] {
        let bundleName = "KnowType_KnowTypeCore.bundle"
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName))
        }
        for baseURL in ancestorURLs(from: Bundle.main.bundleURL, limit: 6) {
            candidates.append(baseURL.appendingPathComponent("Contents/Resources/\(bundleName)"))
            candidates.append(baseURL.appendingPathComponent(bundleName))
        }

        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }

    private static func ancestorURLs(from url: URL, limit: Int) -> [URL] {
        var urls: [URL] = []
        var current = url
        for _ in 0..<max(1, limit) {
            urls.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else {
                break
            }
            current = parent
        }
        return urls
    }

    private static var isSwiftPMBuildOrTestProcess: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return CommandLine.arguments.contains { argument in
            argument.contains(".build") || argument.contains(".xctest")
        }
    }
}
