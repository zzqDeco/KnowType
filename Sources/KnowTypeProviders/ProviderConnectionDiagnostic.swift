import Foundation
import KnowTypeCore

public struct ProviderConnectionDiagnosticResult: Sendable, Equatable {
    public var providerName: String
    public var candidateCount: Int
    public var firstCandidateText: String?

    public init(providerName: String, candidateCount: Int, firstCandidateText: String? = nil) {
        self.providerName = providerName
        self.candidateCount = candidateCount
        self.firstCandidateText = firstCandidateText
    }
}

public struct ProviderConnectionDiagnostic: Sendable {
    public typealias ProviderBuilder = @Sendable (ProviderConfiguration) throws -> any LLMProvider

    private let providerBuilder: ProviderBuilder

    public init(
        providerBuilder: @escaping ProviderBuilder = { configuration in
            try ProviderFactory.makeProvider(configuration: configuration)
        }
    ) {
        self.providerBuilder = providerBuilder
    }

    public func test(configuration: ProviderConfiguration) async throws -> ProviderConnectionDiagnosticResult {
        let provider = try providerBuilder(configuration)
        let response = try await provider.complete(Self.diagnosticRequest)
        guard !response.candidates.isEmpty else {
            throw ProviderError.invalidResponse("diagnostic returned no candidates")
        }
        return ProviderConnectionDiagnosticResult(
            providerName: provider.providerName,
            candidateCount: response.candidates.count,
            firstCandidateText: response.candidates.first?.text
        )
    }

    private static let diagnosticRequest = LLMRequest(
        task: .continuation,
        lockedPrefix: "KnowType",
        locale: .mixed,
        maxCandidates: 1,
        lengthLevel: .short
    )
}
