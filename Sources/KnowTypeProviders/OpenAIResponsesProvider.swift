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
        try ProviderRequestBudget.validate(request)
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
            "instructions": PromptBuilder.systemPrompt(for: request.task),
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
        urlRequest.httpBody = try jsonData(body, task: request.task)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        let outputText = try extractCompletedOutputText(from: raw)
        return try StructuredResponseNormalizer.normalizeText(
            outputText,
            task: request.task,
            diagnostics: diagnostics
        )
    }

    private func extractCompletedOutputText(from raw: Any) throws -> String {
        guard let response = raw as? [String: Any] else {
            throw ProviderError.invalidResponse("response is not an object")
        }

        if let status = response["status"] as? String, status != "completed" {
            if status == "incomplete" {
                let reason = ResponseNormalizer.string(
                    at: ["incomplete_details", "reason"],
                    in: response
                )
                let suffix = reason.map { ": \($0)" } ?? ""
                throw ProviderError.invalidResponse("response incomplete\(suffix)")
            }
            throw ProviderError.invalidResponse("response status is \(status)")
        }
        if let incompleteDetails = response["incomplete_details"],
           !(incompleteDetails is NSNull) {
            throw ProviderError.invalidResponse("response incomplete")
        }

        if let rawOutput = response["output"] {
            guard let output = rawOutput as? [Any] else {
                throw ProviderError.invalidResponse("output is not an array")
            }

            var textParts: [String] = []
            for rawItem in output {
                guard let item = rawItem as? [String: Any],
                      item["type"] as? String == "message" else {
                    continue
                }
                if let status = item["status"] as? String, status != "completed" {
                    throw ProviderError.invalidResponse("output message status is \(status)")
                }
                guard let content = item["content"] as? [Any] else {
                    throw ProviderError.invalidResponse("message content is not an array")
                }
                for rawContentItem in content {
                    guard let contentItem = rawContentItem as? [String: Any],
                          let type = contentItem["type"] as? String else {
                        throw ProviderError.invalidResponse("message content item is invalid")
                    }
                    if type == "refusal" {
                        throw ProviderError.invalidResponse("response contained a refusal")
                    }
                    guard type == "output_text" else {
                        continue
                    }
                    guard let text = contentItem["text"] as? String else {
                        throw ProviderError.invalidResponse("output_text item is missing text")
                    }
                    textParts.append(text)
                }
            }

            guard !textParts.isEmpty else {
                throw ProviderError.invalidResponse("missing output message text")
            }
            return textParts.joined()
        }

        // Some compatible proxies expose the SDK convenience field directly.
        if let outputText = response["output_text"] as? String {
            return outputText
        }
        throw ProviderError.invalidResponse("missing output message text")
    }
}
