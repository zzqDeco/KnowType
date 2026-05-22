import Foundation
import KnowTypeCore

public struct OpenAIChatProvider: LLMProvider {
    public let providerName = "openai_chat"
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
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/chat/completions"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let userPayload = try PromptBuilder.userPayload(for: request)

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "temperature": 0.2,
            "max_tokens": 256,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt],
                ["role": "user", "content": userPayload]
            ]
        ]
        body["response_format"] = structuredOutput
            ? LLMOutputContract.openAIChatResponseFormat(for: request.task)
            : LLMOutputContract.legacyJSONModeResponseFormat()
        urlRequest.httpBody = try jsonData(body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["choices", "0", "message", "content"], in: raw) else {
            throw ProviderError.invalidResponse("missing choices[0].message.content")
        }
        return try StructuredResponseNormalizer.normalizeText(
            content,
            task: request.task,
            diagnostics: diagnostics
        )
    }
}
