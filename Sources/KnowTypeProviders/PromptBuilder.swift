import Foundation
import KnowTypeCore

enum PromptBuilder {
    static let systemPrompt = """
    You are KnowType, a macOS Chinese/English AI input method.
    Return JSON only. For correction, continuation, and polish, use this shape: {"candidates":[{"text":"...","confidence":0.0,"reason":"..."}]}.
    For contextDigest, use this shape: {"markdown":"..."}.
    For continuation, return only the text that comes after locked_prefix. Do not repeat, rewrite, translate, or polish locked_prefix.
    If no safe continuation exists, return {"candidates":[]}.
    For correction, return likely prefixes only. Preserve technical tokens such as API, JSON, FastAPI, iOS, macOS, InputMethodKit, snake_case, camelCase, and userID.
    For contextDigest, summarize typing events into a concise ENV.md generated section. Preserve user notes and do not invent private facts.
    For polish, rewriting is allowed because the user explicitly requested it.
    """

    static func userPayload(for request: LLMRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
