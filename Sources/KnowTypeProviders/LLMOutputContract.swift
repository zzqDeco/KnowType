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
            return "KnowType continuation candidates that contain only text after the locked prefix."
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
        case .correction, .continuation, .polish:
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
                                    "description": task == .continuation
                                        ? "For continuation, only the suffix after locked_prefix."
                                        : "Candidate text."
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

    private var unsupportedKeys: Set<String> = []

    func isUnsupported(_ key: String) -> Bool {
        unsupportedKeys.contains(key)
    }

    func markUnsupported(_ key: String) {
        unsupportedKeys.insert(key)
    }

    func reset() {
        unsupportedKeys.removeAll()
    }
}

enum StructuredOutputFallback {
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
            model
        ]
        .joined(separator: "|")
    }

    static func isStructuredSchemaUnsupported(_ error: Error) -> Bool {
        guard case .httpStatus(let status, let body) = error as? ProviderError,
              status == 400 || status == 422 else {
            return false
        }
        let lowercased = body.lowercased()
        return lowercased.contains("json_schema")
            || lowercased.contains("response_format")
            || lowercased.contains("responseformat")
            || lowercased.contains("response_schema")
            || lowercased.contains("responseschema")
            || lowercased.contains("output_config")
            || lowercased.contains("unsupported")
            || lowercased.contains("unknown field")
    }
}
