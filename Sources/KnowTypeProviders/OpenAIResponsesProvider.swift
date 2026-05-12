import Foundation
import KnowTypeCore

public struct OpenAIResponsesProvider: LLMProvider {
    public let providerName = "openai_responses"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/responses"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try jsonData([
            "model": configuration.model,
            "instructions": PromptBuilder.systemPrompt,
            "input": PromptBuilder.userPayload(for: request),
            "temperature": 0.2,
            "max_output_tokens": 256
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)

        if let outputText = ResponseNormalizer.string(at: ["output_text"], in: raw) {
            return try ResponseNormalizer.normalizeText(outputText)
        }
        if let outputText = ResponseNormalizer.string(at: ["output", "0", "content", "0", "text"], in: raw) {
            return try ResponseNormalizer.normalizeText(outputText)
        }
        throw ProviderError.invalidResponse("missing output_text")
    }
}
