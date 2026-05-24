import CryptoKit
import Foundation
import KnowTypeCore

enum LLMOutputContract {
    static func schemaName(for task: LLMTask) -> String {
        switch task {
        case .contextDigest:
            return "knowtype_context_digest_response"
        case .correction:
            return "knowtype_correction_response"
        case .continuation:
            return "knowtype_continuation_response"
        case .polish:
            return "knowtype_polish_response"
        }
    }

    static func schemaDescription(for task: LLMTask) -> String {
        switch task {
        case .contextDigest:
            return "A local KnowType context digest markdown document."
        case .continuation:
            return "KnowType continuation candidates. With a locked prefix, text is suffix-only; without one, text is a full commit-ready recommendation informed by candidate hints."
        case .correction:
            return "KnowType correction candidates."
        case .polish:
            return "KnowType explicitly requested polish candidates."
        }
    }

    static func jsonSchema(for task: LLMTask) -> [String: Any] {
        switch task {
        case .contextDigest:
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "markdown": [
                        "type": "string",
                        "description": "The complete ENV.md generated section in markdown."
                    ]
                ],
                "required": ["markdown"]
            ]
        case .continuation:
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "candidates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "properties": [
                                "text": [
                                    "type": "string",
                                    "description": "If lockedPrefix is present, only the suffix after lockedPrefix. If lockedPrefix is absent, a full commit-ready recommendation informed by rawInput and candidateHints."
                                ],
                                "confidence": [
                                    "type": "number",
                                    "description": "A confidence score between 0 and 1."
                                ],
                                "reason": [
                                    "type": "string",
                                    "description": "A short reason for diagnostics."
                                ]
                            ],
                            "required": ["text", "confidence", "reason"]
                        ]
                    ]
                ],
                "required": ["candidates"]
            ]
        case .correction, .polish:
            return [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "candidates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "properties": [
                                "text": [
                                    "type": "string",
                                    "description": "Candidate text."
                                ],
                                "confidence": [
                                    "type": "number",
                                    "description": "A confidence score between 0 and 1."
                                ],
                                "reason": [
                                    "type": "string",
                                    "description": "A short reason for diagnostics."
                                ]
                            ],
                            "required": ["text", "confidence", "reason"]
                        ]
                    ]
                ],
                "required": ["candidates"]
            ]
        }
    }

    static func openAIChatResponseFormat(for task: LLMTask) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": schemaName(for: task),
                "description": schemaDescription(for: task),
                "strict": true,
                "schema": jsonSchema(for: task)
            ]
        ]
    }

    static func openAIResponsesTextFormat(for task: LLMTask) -> [String: Any] {
        [
            "type": "json_schema",
            "name": schemaName(for: task),
            "description": schemaDescription(for: task),
            "strict": true,
            "schema": jsonSchema(for: task)
        ]
    }

    static func geminiResponseSchema(for task: LLMTask) -> [String: Any] {
        jsonSchema(for: task)
    }

    static func anthropicOutputConfig(for task: LLMTask) -> [String: Any] {
        [
            "format": [
                "type": "json_schema",
                "name": schemaName(for: task),
                "description": schemaDescription(for: task),
                "strict": true,
                "schema": jsonSchema(for: task)
            ]
        ]
    }

    static func legacyJSONModeResponseFormat() -> [String: Any] {
        ["type": "json_object"]
    }
}

actor StructuredOutputCapabilityCache {
    static let shared = StructuredOutputCapabilityCache()

    private var unsupportedKeys: [String: StructuredOutputFallback.Mode] = [:]

    func fallbackMode(for key: String) -> StructuredOutputFallback.Mode? {
        unsupportedKeys[key]
    }

    func markUnsupported(_ key: String, mode: StructuredOutputFallback.Mode) {
        unsupportedKeys[key] = mode
    }

    func reset() {
        unsupportedKeys.removeAll()
    }
}

enum StructuredOutputFallback {
    enum Mode: Equatable, Sendable {
        case jsonObject
        case promptOnly
    }

    static let unsupportedDiagnostic = "structured_schema_unsupported"
    static let unsupportedCachedDiagnostic = "structured_schema_unsupported_cached"

    static func capabilityKey(
        providerName: String,
        configuration: ProviderConfiguration,
        model: String
    ) -> String {
        [
            providerName,
            configuration.baseURL.absoluteString,
            model,
            apiKeyFingerprint(configuration.apiKey),
            headersFingerprint(configuration.headers)
        ]
        .joined(separator: "|")
    }

    static func isStructuredSchemaUnsupported(_ error: Error) -> Bool {
        fallbackMode(for: error) != nil
    }

    static func fallbackMode(for error: Error) -> Mode? {
        guard case .httpStatus(let status, let body) = error as? ProviderError,
              status == 400 || status == 422 else {
            return nil
        }
        let lowercased = body.lowercased()
        guard hasStructuredOutputMarker(lowercased),
              hasSchemaCapabilityFailureMarker(lowercased) else {
            return nil
        }
        return hasPromptOnlyFallbackMarker(lowercased) ? .promptOnly : .jsonObject
    }

    private static func hasStructuredOutputMarker(_ lowercased: String) -> Bool {
        lowercased.contains("json_schema")
            || lowercased.contains("response_format")
            || lowercased.contains("responseformat")
            || lowercased.contains("response_schema")
            || lowercased.contains("responseschema")
            || lowercased.contains("output_config")
            || lowercased.contains("outputconfig")
            || lowercased.contains("text.format")
            || lowercased.contains("'text'")
            || lowercased.contains("\"text\"")
    }

    private static func hasSchemaCapabilityFailureMarker(_ lowercased: String) -> Bool {
        lowercased.contains("unsupported")
            || lowercased.contains("not supported")
            || lowercased.contains("unknown field")
            || lowercased.contains("unknown parameter")
            || lowercased.contains("unrecognized field")
            || lowercased.contains("unrecognized request argument")
            || lowercased.contains("invalid parameter")
            || lowercased.contains("unexpected field")
            || lowercased.contains("extra inputs are not permitted")
            || lowercased.contains("extra_forbidden")
    }

    private static func hasPromptOnlyFallbackMarker(_ lowercased: String) -> Bool {
        (
            lowercased.contains("'text'")
                || lowercased.contains("\"text\"")
                || lowercased.contains("text.format")
        )
            && !lowercased.contains("json_schema")
            && !lowercased.contains("response_format")
            && !lowercased.contains("responseformat")
            && !lowercased.contains("response_schema")
            && !lowercased.contains("responseschema")
    }

    private static func apiKeyFingerprint(_ apiKey: String?) -> String {
        guard let apiKey,
              !apiKey.isEmpty else {
            return "api-key:none"
        }
        return "api-key:\(sha256(apiKey))"
    }

    private static func headersFingerprint(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else {
            return "headers:none"
        }
        return headers
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { "\($0.key):\(sha256($0.value))" }
            .joined(separator: ",")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
