import Foundation

public protocol ProviderModelDiscovering: Sendable {
    func resolvedModel(for configuration: ProviderConfiguration) async throws -> String
}

public actor OpenAICompatibleModelDiscovery: ProviderModelDiscovering {
    private let httpClient: any HTTPClient
    private var cache: [String: String] = [:]

    public init(httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    public func resolvedModel(for configuration: ProviderConfiguration) async throws -> String {
        let trimmedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.requiresDiscovery(trimmedModel) else {
            return trimmedModel
        }
        guard Self.allowsModelDiscovery(for: configuration.baseURL) else {
            throw ProviderError.invalidResponse("model is required for remote OpenAI-compatible providers")
        }

        let key = cacheKey(for: configuration)
        if let cached = cache[key] {
            return cached
        }

        let discovered = try await discoverPreferredModelID(configuration: configuration)
        cache[key] = discovered
        return discovered
    }

    public static func requiresDiscovery(_ model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let lowercased = trimmed.lowercased()
        return lowercased == "<model>"
            || lowercased == "<model-id>"
            || lowercased == "{{model}}"
            || lowercased == "{{model_id}}"
            || lowercased == "placeholder"
            || lowercased == "replace-me"
            || lowercased == "replace_me"
            || lowercased == "your-model-id"
            || lowercased == "your_model_id"
            || lowercased == "todo"
    }

    public static func allowsModelDiscovery(for baseURL: URL) -> Bool {
        guard let host = baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".local")
    }

    private func discoverPreferredModelID(configuration: ProviderConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.endpoint(path: "/v1/models"))
        request.timeoutInterval = configuration.timeoutSeconds
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await httpClient.data(for: request)
        try validateHTTPResponse(response, data: data)

        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any],
              let models = object["data"] as? [[String: Any]] else {
            throw ProviderError.invalidResponse("missing models data")
        }

        let modelIDs = models.compactMap { model -> String? in
            guard let id = model["id"] as? String else {
                return nil
            }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !modelIDs.isEmpty else {
            throw ProviderError.invalidResponse("empty models data")
        }

        guard let modelID = modelIDs.first(where: Self.isLikelyCompletionModel) else {
            throw ProviderError.invalidResponse("no completion-capable models data")
        }
        return modelID
    }

    private static func isLikelyCompletionModel(_ modelID: String) -> Bool {
        let lowercased = modelID.lowercased()
        let unsupportedFragments = [
            "dall-e",
            "embedding",
            "gpt-image",
            "image",
            "moderation",
            "tts",
            "whisper"
        ]
        guard unsupportedFragments.allSatisfy({ !lowercased.contains($0) }) else {
            return false
        }

        let tokens = lowercased.split { character in
            !character.isLetter && !character.isNumber
        }
        return !tokens.contains("embed")
    }

    private func cacheKey(for configuration: ProviderConfiguration) -> String {
        [
            configuration.kind.rawValue,
            configuration.baseURL.absoluteString,
            apiKeyFingerprint(configuration.apiKey),
            configuration.headers
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: "|")
        ].joined(separator: "\n")
    }

    private func apiKeyFingerprint(_ apiKey: String?) -> String {
        guard let apiKey,
              !apiKey.isEmpty else {
            return "api-key:none"
        }
        return "api-key:\(apiKey.hashValue)"
    }
}
