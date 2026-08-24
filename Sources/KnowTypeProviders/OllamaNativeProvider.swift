import Foundation
import KnowTypeCore

public struct OllamaNativeProvider: LLMProvider {
    public let providerName = "ollama_native"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/api/chat"))
        applyCommonHeaders(&urlRequest, configuration: configuration)

        urlRequest.httpBody = try jsonData([
            "model": configuration.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(for: request.task)],
                ["role": "user", "content": PromptBuilder.userPayload(for: request)]
            ],
            "options": [
                "temperature": 0.2,
                "num_predict": 256
            ]
        ], task: request.task)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["message", "content"], in: raw) else {
            throw ProviderError.invalidResponse("missing message.content")
        }
        return try StructuredResponseNormalizer.normalizeText(content, task: request.task)
    }
}
