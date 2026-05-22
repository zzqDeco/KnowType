import Foundation
import KnowTypeCore

public struct OpenAIResponsesProvider: LLMProvider {
    public let providerName = "openai_responses"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient
    private let modelDiscovery: any ProviderModelDiscovering

    public init(
        configuration: ProviderConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        modelDiscovery: (any ProviderModelDiscovering)? = nil
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.modelDiscovery = modelDiscovery ?? OpenAICompatibleModelDiscovery(httpClient: httpClient)
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let model = try await modelDiscovery.resolvedModel(for: configuration)
        let cacheKey = StructuredOutputFallback.capabilityKey(
            providerName: providerName,
            configuration: configuration,
            model: model
        )
        if await StructuredOutputCapabilityCache.shared.isUnsupported(cacheKey) {
            return try await complete(
                request,
                model: model,
                structuredOutput: false,
                diagnostics: [StructuredOutputFallback.unsupportedCachedDiagnostic]
            )
        }

        do {
            return try await complete(request, model: model, structuredOutput: true)
        } catch {
            guard StructuredOutputFallback.isStructuredSchemaUnsupported(error) else {
                throw error
            }
            await StructuredOutputCapabilityCache.shared.markUnsupported(cacheKey)
            return try await complete(
                request,
                model: model,
                structuredOutput: false,
                diagnostics: [StructuredOutputFallback.unsupportedDiagnostic]
            )
        }
    }

    private func complete(
        _ request: LLMRequest,
        model: String,
        structuredOutput: Bool,
        diagnostics: [String] = []
    ) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/responses"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let textFormat = structuredOutput
            ? LLMOutputContract.openAIResponsesTextFormat(for: request.task)
            : LLMOutputContract.legacyJSONModeResponseFormat()
        urlRequest.httpBody = try jsonData([
            "model": model,
            "instructions": PromptBuilder.systemPrompt,
            "input": PromptBuilder.userPayload(for: request),
            "temperature": 0.2,
            "max_output_tokens": 256,
            "text": [
                "format": textFormat
            ]
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)

        if let outputText = ResponseNormalizer.string(at: ["output_text"], in: raw) {
            return try StructuredResponseNormalizer.normalizeText(
                outputText,
                task: request.task,
                diagnostics: diagnostics
            )
        }
        if let outputText = ResponseNormalizer.string(at: ["output", "0", "content", "0", "text"], in: raw) {
            return try StructuredResponseNormalizer.normalizeText(
                outputText,
                task: request.task,
                diagnostics: diagnostics
            )
        }
        throw ProviderError.invalidResponse("missing output_text")
    }
}
