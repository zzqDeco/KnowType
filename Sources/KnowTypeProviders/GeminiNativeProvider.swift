import Foundation
import KnowTypeCore

public struct GeminiNativeProvider: LLMProvider {
    public let providerName = "gemini_native"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var components = URLComponents(url: configuration.endpoint(path: "/v1beta/models/\(configuration.model):generateContent"), resolvingAgainstBaseURL: false)!
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }
        var urlRequest = URLRequest(url: components.url!)
        applyCommonHeaders(&urlRequest, configuration: configuration)

        let prompt = "\(PromptBuilder.systemPrompt)\n\n\(try PromptBuilder.userPayload(for: request))"
        urlRequest.httpBody = try jsonData([
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 256,
                "responseMimeType": "application/json"
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ]
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["candidates", "0", "content", "parts", "0", "text"], in: raw) else {
            throw ProviderError.invalidResponse("missing candidates[0].content.parts[0].text")
        }
        return try ResponseNormalizer.normalizeText(content)
    }
}
