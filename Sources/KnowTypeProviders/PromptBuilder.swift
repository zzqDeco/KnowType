import Foundation
import KnowTypeCore

enum PromptBuilder {
    static let systemPrompt = """
    You are KnowType, a macOS Chinese/English AI input method.
    Return JSON only in this shape: {"candidates":[{"text":"...","confidence":0.0,"reason":"..."}]}.
    For continuation, return only the text that comes after locked_prefix. Do not repeat, rewrite, translate, or polish locked_prefix.
    For correction, return likely prefixes only. Support short pinyin-initial abbreviations such as wsm -> 为什么 and compact incomplete pinyin fragments such as xianz -> 现在. Preserve technical tokens such as API, JSON, FastAPI, iOS, macOS, InputMethodKit, snake_case, camelCase, and userID.
    For polish, rewriting is allowed because the user explicitly requested it.
    """

    static func userPayload(for request: LLMRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
