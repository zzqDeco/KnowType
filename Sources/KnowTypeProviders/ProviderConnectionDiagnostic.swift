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
        let lockedPrefix = Self.diagnosticRequest.lockedPrefix ?? ""
        let usableCandidates = response.candidates.compactMap { candidate -> LLMCandidate? in
            guard PrefixContinuationEngine.sanitizeContinuation(
                candidate.text,
                lockedPrefix: lockedPrefix
            ) != nil else {
                return nil
            }
            return candidate
        }
        guard !usableCandidates.isEmpty else {
            throw ProviderError.invalidResponse("diagnostic returned no usable continuation candidates")
        }
        return ProviderConnectionDiagnosticResult(
            providerName: provider.providerName,
            candidateCount: usableCandidates.count,
            firstCandidateText: usableCandidates.first?.text
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
