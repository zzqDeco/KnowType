import Foundation

public struct TraditionalInputLexiconFileSource: Sendable {
    private let catalogLoader: TraditionalInputLexiconCatalogLoader

    public init(catalogLoader: TraditionalInputLexiconCatalogLoader = TraditionalInputLexiconCatalogLoader()) {
        self.catalogLoader = catalogLoader
    }

    public func loadFiles(_ fileURLs: [URL]) -> TraditionalInputLexiconCatalog {
        var resources: [TraditionalInputLexiconResource] = []
        var diagnostics: [TraditionalInputLexiconDiagnostic] = []

        for fileURL in fileURLs {
            let resourceID = fileURL.lastPathComponent
            guard let format = Self.format(for: fileURL) else {
                diagnostics.append(
                    TraditionalInputLexiconDiagnostic(
                        resourceID: resourceID,
                        error: .unsupportedFormat(fileURL.pathExtension)
                    )
                )
                continue
            }

            do {
                resources.append(
                    TraditionalInputLexiconResource(
                        id: resourceID,
                        format: format,
                        data: try Data(contentsOf: fileURL)
                    )
                )
            } catch {
                diagnostics.append(
                    TraditionalInputLexiconDiagnostic(
                        resourceID: resourceID,
                        error: .unreadableResource(error.localizedDescription)
                    )
                )
            }
        }

        let catalog = catalogLoader.load(resources)
        return TraditionalInputLexiconCatalog(
            entries: catalog.entries,
            diagnostics: diagnostics + catalog.diagnostics
        )
    }

    public func loadDirectory(_ directoryURL: URL) -> TraditionalInputLexiconCatalog {
        do {
            return loadFiles(try Self.lexiconFileURLs(in: directoryURL))
        } catch {
            return TraditionalInputLexiconCatalog(
                entries: [],
                diagnostics: [
                    TraditionalInputLexiconDiagnostic(
                        resourceID: directoryURL.lastPathComponent,
                        error: .unreadableResource(error.localizedDescription)
                    )
                ]
            )
        }
    }

    public static func format(for fileURL: URL) -> TraditionalInputLexiconResourceFormat? {
        switch fileURL.pathExtension.lowercased() {
        case "json":
            return .json
        case "tsv":
            return .tsv
        default:
            return nil
        }
    }

    public static func isLexiconResourceFile(_ fileURL: URL) -> Bool {
        !fileURL.lastPathComponent.hasPrefix(".")
            && !fileURL.lastPathComponent.hasSuffix(".metadata.json")
            && format(for: fileURL) != nil
    }

    private static func lexiconFileURLs(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        )
        .filter { url in
            guard isLexiconResourceFile(url) else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory != true && values?.isHidden != true
        }
        .sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }
}
