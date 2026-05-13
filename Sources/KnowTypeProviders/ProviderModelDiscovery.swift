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

        let key = cacheKey(for: configuration)
        if let cached = cache[key] {
            return cached
        }

        let discovered = try await discoverFirstModelID(configuration: configuration)
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

    private func discoverFirstModelID(configuration: ProviderConfiguration) async throws -> String {
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

        guard let modelID = models.compactMap({ model -> String? in
            guard let id = model["id"] as? String else {
                return nil
            }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }).first else {
            throw ProviderError.invalidResponse("empty models data")
        }

        return modelID
    }

    private func cacheKey(for configuration: ProviderConfiguration) -> String {
        [
            configuration.kind.rawValue,
            configuration.baseURL.absoluteString,
            configuration.headers
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: "|")
        ].joined(separator: "\n")
    }
}
