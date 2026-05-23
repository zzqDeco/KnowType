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
        if let fallbackMode = await StructuredOutputCapabilityCache.shared.fallbackMode(for: cacheKey) {
            return try await complete(
                request,
                model: model,
                outputFormatMode: .fallback(fallbackMode),
                diagnostics: [StructuredOutputFallback.unsupportedCachedDiagnostic]
            )
        }

        do {
            return try await complete(request, model: model, outputFormatMode: .jsonSchema)
        } catch {
            guard StructuredOutputFallback.isStructuredSchemaUnsupported(error) else {
                throw error
            }
            let fallbackMode = StructuredOutputFallback.fallbackMode(for: error) ?? .jsonObject
            await StructuredOutputCapabilityCache.shared.markUnsupported(cacheKey, mode: fallbackMode)
            return try await complete(
                request,
                model: model,
                outputFormatMode: .fallback(fallbackMode),
                diagnostics: [StructuredOutputFallback.unsupportedDiagnostic]
            )
        }
    }

    private enum OutputFormatMode {
        case jsonSchema
        case jsonObject
        case promptOnly

        static func fallback(_ mode: StructuredOutputFallback.Mode) -> Self {
            switch mode {
            case .jsonObject:
                return .jsonObject
            case .promptOnly:
                return .promptOnly
            }
        }
    }

    private func complete(
        _ request: LLMRequest,
        model: String,
        outputFormatMode: OutputFormatMode,
        diagnostics: [String] = []
    ) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/responses"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let userPayload = try PromptBuilder.userPayload(for: request)
        var body: [String: Any] = [
            "model": model,
            "instructions": PromptBuilder.systemPrompt,
            "input": userPayload,
            "temperature": 0.2,
            "max_output_tokens": 256
        ]
        switch outputFormatMode {
        case .jsonSchema:
            body["text"] = [
                "format": LLMOutputContract.openAIResponsesTextFormat(for: request.task)
            ]
        case .jsonObject:
            body["text"] = [
                "format": LLMOutputContract.legacyJSONModeResponseFormat()
            ]
        case .promptOnly:
            break
        }
        urlRequest.httpBody = try jsonData(body)

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
