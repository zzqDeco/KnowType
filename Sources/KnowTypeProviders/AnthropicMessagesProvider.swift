import Foundation
import KnowTypeCore

public struct AnthropicMessagesProvider: LLMProvider {
    public let providerName = "anthropic_messages"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let cacheKey = StructuredOutputFallback.capabilityKey(
            providerName: providerName,
            configuration: configuration,
            model: configuration.model
        )
        if await StructuredOutputCapabilityCache.shared.fallbackMode(for: cacheKey) != nil {
            return try await complete(
                request,
                structuredOutput: false,
                diagnostics: [StructuredOutputFallback.unsupportedCachedDiagnostic]
            )
        }

        do {
            return try await complete(request, structuredOutput: true)
        } catch {
            guard StructuredOutputFallback.isStructuredSchemaUnsupported(error) else {
                throw error
            }
            let fallbackMode = StructuredOutputFallback.fallbackMode(for: error) ?? .jsonObject
            await StructuredOutputCapabilityCache.shared.markUnsupported(cacheKey, mode: fallbackMode)
            return try await complete(
                request,
                structuredOutput: false,
                diagnostics: [StructuredOutputFallback.unsupportedDiagnostic]
            )
        }
    }

    private func complete(
        _ request: LLMRequest,
        structuredOutput: Bool,
        diagnostics: [String] = []
    ) async throws -> LLMResponse {
        let urlRequest = try makeRequest(for: request, structuredOutput: structuredOutput)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["content", "0", "text"], in: raw) else {
            throw ProviderError.invalidResponse("missing content[0].text")
        }
        return try StructuredResponseNormalizer.normalizeText(
            content,
            task: request.task,
            diagnostics: diagnostics
        )
    }

    private func makeRequest(
        for request: LLMRequest,
        structuredOutput: Bool
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/messages"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        if urlRequest.value(forHTTPHeaderField: "anthropic-version") == nil {
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        let userPayload = try PromptBuilder.userPayload(for: request)

        var body: [String: Any] = [
            "model": configuration.model,
            "system": PromptBuilder.systemPrompt(for: request.task),
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": userPayload]
            ]
        ]
        if structuredOutput {
            body["output_config"] = LLMOutputContract.anthropicOutputConfig(for: request.task)
        }
        urlRequest.httpBody = try jsonData(body)
        return urlRequest
    }
}
