import Foundation

public struct TraditionalInputLexiconResource: Sendable, Equatable {
    public var id: String
    public var format: TraditionalInputLexiconResourceFormat
    public var data: Data

    public init(
        id: String,
        format: TraditionalInputLexiconResourceFormat,
        data: Data
    ) {
        self.id = id
        self.format = format
        self.data = data
    }
}

public struct TraditionalInputLexiconDiagnostic: Sendable, Equatable {
    public var resourceID: String
    public var error: TraditionalInputLexiconResourceError

    public init(
        resourceID: String,
        error: TraditionalInputLexiconResourceError
    ) {
        self.resourceID = resourceID
        self.error = error
    }
}

public struct TraditionalInputLexiconCatalog: Sendable, Equatable {
    public var entries: [TraditionalInputLexiconEntry]
    public var diagnostics: [TraditionalInputLexiconDiagnostic]

    public init(
        entries: [TraditionalInputLexiconEntry],
        diagnostics: [TraditionalInputLexiconDiagnostic] = []
    ) {
        self.entries = entries
        self.diagnostics = diagnostics
    }

    public var hasDiagnostics: Bool {
        !diagnostics.isEmpty
    }

    public func makeEngine(scheme: TraditionalInputEngine.Scheme = .fullPinyin) -> TraditionalInputEngine {
        TraditionalInputEngine(
            scheme: scheme,
            additionalLexiconEntries: entries
        )
    }
}

public struct TraditionalInputLexiconCatalogLoader: Sendable {
    private let resourceLoader: TraditionalInputLexiconResourceLoader

    public init(resourceLoader: TraditionalInputLexiconResourceLoader = TraditionalInputLexiconResourceLoader()) {
        self.resourceLoader = resourceLoader
    }

    public func load(_ resources: [TraditionalInputLexiconResource]) -> TraditionalInputLexiconCatalog {
        var entries: [TraditionalInputLexiconEntry] = []
        var diagnostics: [TraditionalInputLexiconDiagnostic] = []

        for resource in resources {
            do {
                entries.append(contentsOf: try resourceLoader.load(resource.data, format: resource.format))
            } catch let error as TraditionalInputLexiconResourceError {
                diagnostics.append(
                    TraditionalInputLexiconDiagnostic(
                        resourceID: resource.id,
                        error: error
                    )
                )
            } catch {
                diagnostics.append(
                    TraditionalInputLexiconDiagnostic(
                        resourceID: resource.id,
                        error: .invalidJSON(error.localizedDescription)
                    )
                )
            }
        }

        return TraditionalInputLexiconCatalog(entries: entries, diagnostics: diagnostics)
    }
}
