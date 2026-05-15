import Foundation

public enum ProviderProfileTemplates {
    public static func defaultProfiles() -> [ProviderProfile] {
        ProviderKind.allCases.map { defaultProfile(kind: $0, isDefault: $0 == .openAIChat) }
    }

    public static func defaultProfile(kind: ProviderKind, isDefault: Bool = false) -> ProviderProfile {
        switch kind {
        case .openAIChat:
            return ProviderProfile(
                displayName: "Local OpenAI Compatible",
                kind: kind,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "",
                isDefault: isDefault
            )
        case .openAIResponses:
            return ProviderProfile(
                displayName: "OpenAI Responses",
                kind: kind,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_responses.apiKey",
                isDefault: isDefault
            )
        case .anthropicMessages:
            return ProviderProfile(
                displayName: "Anthropic Messages",
                kind: kind,
                baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude-3-5-haiku-latest",
                headers: ["anthropic-version": "2023-06-01"],
                secretName: "knowtype.anthropic_messages.apiKey",
                isDefault: isDefault
            )
        case .geminiNative:
            return ProviderProfile(
                displayName: "Gemini Native",
                kind: kind,
                baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                model: "gemini-1.5-flash",
                secretName: "knowtype.gemini_native.apiKey",
                isDefault: isDefault
            )
        case .ollamaNative:
            return ProviderProfile(
                displayName: "Ollama Native",
                kind: kind,
                baseURL: URL(string: "http://localhost:11434")!,
                model: "llama3.2",
                isDefault: isDefault
            )
        case .customHTTP:
            return ProviderProfile(
                displayName: "Custom HTTP",
                kind: kind,
                baseURL: URL(string: "https://api.example.com/v1/complete")!,
                model: "",
                customBodyTemplate: #"{"request":{{request_json}}}"#,
                customResponsePath: "candidates",
                isDefault: isDefault
            )
        }
    }
}
