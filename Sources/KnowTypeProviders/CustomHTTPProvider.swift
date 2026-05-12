import Foundation
import KnowTypeCore

public struct CustomHTTPProvider: LLMProvider {
    public let providerName = "custom_http"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.baseURL)
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty, urlRequest.value(forHTTPHeaderField: "Authorization") == nil {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        if let template = configuration.customBodyTemplate {
            let rendered = try render(template: template, request: request)
            guard let body = rendered.data(using: .utf8) else {
                throw ProviderError.invalidTemplate("template is not UTF-8")
            }
            urlRequest.httpBody = body
        } else {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        }

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        let path = configuration.customResponsePath ?? "candidates"
        let value = ResponseNormalizer.value(at: path.split(separator: ".").map(String.init), in: raw) ?? raw

        if let text = value as? String {
            return try ResponseNormalizer.normalizeText(text)
        }
        if let candidates = ResponseNormalizer.candidates(from: value) {
            return LLMResponse(candidates: candidates)
        }
        throw ProviderError.invalidResponse("custom response path did not contain candidates")
    }

    private func render(template: String, request: LLMRequest) throws -> String {
        let requestData = try JSONEncoder().encode(request)
        let requestJSON = String(data: requestData, encoding: .utf8) ?? "{}"
        var output = template
        let replacements: [String: String] = [
            "{{task}}": request.task.rawValue,
            "{{raw_input}}": escapeJSONString(request.rawInput ?? ""),
            "{{locked_prefix}}": escapeJSONString(request.lockedPrefix ?? ""),
            "{{locale}}": request.locale.rawValue,
            "{{max_candidates}}": String(request.maxCandidates),
            "{{length_level}}": request.lengthLevel?.rawValue ?? "",
            "{{request_json}}": requestJSON
        ]
        for (key, value) in replacements {
            output = output.replacingOccurrences(of: key, with: value)
        }
        return output
    }

    private func escapeJSONString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        let encoded = String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
        return String(encoded.dropFirst().dropLast())
    }
}
