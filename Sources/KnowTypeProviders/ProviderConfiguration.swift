import Foundation
import KnowTypeCore

public enum ProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case openAIChat = "openai_chat"
    case openAIResponses = "openai_responses"
    case anthropicMessages = "anthropic_messages"
    case geminiNative = "gemini_native"
    case ollamaNative = "ollama_native"
    case customHTTP = "custom_http"
}

public struct ProviderRequestBudgetError: Error, Codable, Sendable, Equatable {
    public var task: LLMTask
    public var component: String
    public var byteCount: Int
    public var limit: Int

    public init(task: LLMTask, component: String, byteCount: Int, limit: Int) {
        self.task = task
        self.component = component
        self.byteCount = byteCount
        self.limit = limit
    }
}

public struct ProviderRateLimitError: Error, Sendable, Equatable {
    public var statusCode: Int
    public var retryAfterSeconds: TimeInterval?
    public var bodyByteCount: Int

    public init(statusCode: Int = 429, retryAfterSeconds: TimeInterval?, bodyByteCount: Int) {
        self.statusCode = statusCode
        self.retryAfterSeconds = retryAfterSeconds
        self.bodyByteCount = bodyByteCount
    }
}

public enum ProviderRequestBudget {
    public static let recommendationLogicalPayload = 32 * 1_024
    public static let recommendationHTTPBody = 64 * 1_024
    public static let digestEvents = 48 * 1_024
    public static let digestEnvironmentProjection = 8 * 1_024
    public static let digestLogicalPayload = 64 * 1_024
    public static let digestHTTPBody = 96 * 1_024
    public static let generated = 4 * 1_024
    public static let userNotes = 4 * 1_024
    public static let correction = 4 * 1_024
    public static let lexical = 6 * 1_024
    public static let feedback = 4 * 1_024
    public static let rawInput = 4 * 1_024
    public static let lockedPrefix = 4 * 1_024

    public static func encodedPayload(for request: LLMRequest) throws -> Data {
        try validate(request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let limit = request.task == .contextDigest ? digestLogicalPayload : recommendationLogicalPayload
        guard data.count <= limit else {
            throw ProviderRequestBudgetError(task: request.task, component: "logical_payload", byteCount: data.count, limit: limit)
        }
        return data
    }

    public static func validate(_ request: LLMRequest) throws {
        if request.task != .contextDigest {
            try check(request.rawInput, component: "raw_input", limit: rawInput, task: request.task)
            try check(request.lockedPrefix, component: "locked_prefix", limit: lockedPrefix, task: request.task)
        } else {
            try check(request.rawInput, component: "digest_events", limit: digestEvents, task: request.task)
        }
        for (name, value) in request.contextDocuments {
            let limit: Int
            switch name {
            case "ENV.md": limit = digestEnvironmentProjection
            case "CORRECTION.md": limit = correction
            case "LEXICAL_PROFILE.md": limit = lexical
            case "AI_FEEDBACK.md": limit = feedback
            default: continue
            }
            try check(value, component: name, limit: limit, task: request.task)
            if name == "ENV.md" { try validateEnvironmentProjection(value, task: request.task) }
        }
    }

    public static func validateHTTPBody(_ data: Data, task: LLMTask) throws {
        let limit = task == .contextDigest ? digestHTTPBody : recommendationHTTPBody
        guard data.count <= limit else {
            throw ProviderRequestBudgetError(task: task, component: "http_body", byteCount: data.count, limit: limit)
        }
    }

    private static func check(_ value: String?, component: String, limit: Int, task: LLMTask) throws {
        guard let value else { return }
        let count = Data(value.utf8).count
        guard count <= limit else {
            throw ProviderRequestBudgetError(task: task, component: component, byteCount: count, limit: limit)
        }
    }

    private static func validateEnvironmentProjection(_ value: String, task: LLMTask) throws {
        let startMarker = "<!-- KNOWTYPE:BEGIN GENERATED -->"
        let endMarker = "<!-- KNOWTYPE:END GENERATED -->"
        let notesHeading = "## User Notes"
        if let start = value.range(of: startMarker),
           let end = value.range(of: endMarker, range: start.upperBound..<value.endIndex) {
            let body = environmentBody(
                value[start.upperBound..<end.lowerBound],
                dropLeadingSeparator: true,
                dropTrailingSeparator: true
            )
            try check(body, component: "generated", limit: generated, task: task)
        }
        if let notes = value.range(of: notesHeading) {
            let body = environmentBody(
                value[notes.upperBound...],
                dropLeadingSeparator: true,
                dropTrailingSeparator: false
            )
            try check(body, component: "user_notes", limit: userNotes, task: task)
        }
    }

    private static func environmentBody(
        _ value: Substring,
        dropLeadingSeparator: Bool,
        dropTrailingSeparator: Bool
    ) -> String {
        var body = String(value)
        if dropLeadingSeparator {
            if body.hasPrefix("\r\n") {
                body.removeFirst(2)
            } else if body.hasPrefix("\n") {
                body.removeFirst()
            }
        }
        if dropTrailingSeparator {
            if body.hasSuffix("\r\n") {
                body.removeLast(2)
            } else if body.hasSuffix("\n") {
                body.removeLast()
            }
        }
        return body
    }
}

public struct ProviderConfiguration: Codable, Sendable, Equatable {
    public var kind: ProviderKind
    public var baseURL: URL
    public var apiKey: String?
    public var model: String
    public var timeoutSeconds: TimeInterval
    public var headers: [String: String]
    public var customBodyTemplate: String?
    public var customResponsePath: String?

    public init(
        kind: ProviderKind,
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        timeoutSeconds: TimeInterval = 20,
        headers: [String: String] = [:],
        customBodyTemplate: String? = nil,
        customResponsePath: String? = nil
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.customBodyTemplate = customBodyTemplate
        self.customResponsePath = customResponsePath
    }

    func endpoint(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if (basePath == "v1" || basePath.hasSuffix("/v1")),
           suffix.hasPrefix("v1/") {
            suffix.removeFirst("v1/".count)
        }
        if !suffix.isEmpty {
            basePath = basePath.isEmpty ? suffix : "\(basePath)/\(suffix)"
        }
        components.path = "/\(basePath)"
        return components.url!
    }
}

public enum ProviderError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidResponse(String)
    case httpStatus(Int, String)
    case missingAPIKey
    case invalidTemplate(String)
    case unsupportedKind(ProviderKind)

    public var description: String {
        switch self {
        case .invalidResponse(let message):
            return "Invalid provider response: \(message)"
        case .httpStatus(let status, let body):
            return "Provider returned HTTP \(status): \(body)"
        case .missingAPIKey:
            return "Provider requires an API key"
        case .invalidTemplate(let message):
            return "Invalid custom HTTP template: \(message)"
        case .unsupportedKind(let kind):
            return "Unsupported provider kind: \(kind.rawValue)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public enum ProviderFactory {
    public static func makeProvider(
        configuration: ProviderConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws -> any LLMProvider {
        switch configuration.kind {
        case .openAIChat:
            return OpenAIChatProvider(configuration: configuration, httpClient: httpClient)
        case .openAIResponses:
            return OpenAIResponsesProvider(configuration: configuration, httpClient: httpClient)
        case .anthropicMessages:
            return AnthropicMessagesProvider(configuration: configuration, httpClient: httpClient)
        case .geminiNative:
            return GeminiNativeProvider(configuration: configuration, httpClient: httpClient)
        case .ollamaNative:
            return OllamaNativeProvider(configuration: configuration, httpClient: httpClient)
        case .customHTTP:
            return CustomHTTPProvider(configuration: configuration, httpClient: httpClient)
        }
    }
}
