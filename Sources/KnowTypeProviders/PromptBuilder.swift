import Foundation
import KnowTypeCore

enum PromptBuilder {
    static func systemPrompt(for task: LLMTask) -> String {
        switch task {
        case .continuation:
            return continuationPrompt
        case .contextDigest:
            return contextDigestPrompt
        case .correction:
            return correctionPrompt
        case .polish:
            return polishPrompt
        }
    }

    private static let continuationPrompt = """
    You are a suffix generator inside the KnowType input method.
    Output JSON only: {"candidates":[{"text":"recommendation","confidence":0.0,"reason":"short reason"}]}.
    The user message is a JSON object. Read lockedPrefix, rawInput, locale, appContext, maxCandidates, lengthLevel, and contextDocuments.
    lockedPrefix is text the user has already confirmed. Unconfirmed input-method candidates are not user intent.
    Rules:
    - If lockedPrefix is present, text must be only the suffix after lockedPrefix. Do not include, paraphrase, translate, rewrite, or polish lockedPrefix.
    - If lockedPrefix is absent, text must be a complete commit-ready recommendation inferred from rawInput, contextDocuments, appContext, and locale.
    - Do not assume the input method's first conversion candidate or current highlighted candidate is user intent.
    - Prefer one concise, immediately useful recommendation in the same language and intent implied by lockedPrefix, rawInput, contextDocuments, and locale.
    - Empty candidates are allowed only when lockedPrefix/rawInput are unsafe, impossible, or nonsensical.
    - Preserve English technical tokens exactly, including API, JSON, macOS, InputMethodKit, snake_case, and camelCase.
    Good: lockedPrefix="我觉得这个方案" text="还可以再细化一下。"
    Good: lockedPrefix=null rawInput="zhege api de yanchi" text="这个 API 的延迟主要卡在网络和序列化两段。"
    Good: lockedPrefix=null rawInput="this approach" text="This approach keeps the hot path simple."
    Bad: lockedPrefix="我觉得这个方案" text="我觉得这个方案还可以" because text repeats lockedPrefix.
    """

    private static let correctionPrompt = """
    You are KnowType, a macOS Chinese/English AI input method.
    Return JSON only with this shape: {"candidates":[{"text":"...","confidence":0.0,"reason":"..."}]}.
    For correction, return likely corrected prefixes only. Do not continue the sentence.
    Preserve technical tokens such as API, JSON, FastAPI, iOS, macOS, InputMethodKit, snake_case, camelCase, and userID.
    """

    private static let contextDigestPrompt = """
    You are KnowType, a macOS Chinese/English AI input method.
    Return JSON only with this shape: {"markdown":"..."}.
    Summarize typing events into a concise ENV.md generated section.
    Preserve user notes and do not invent private facts.
    """

    private static let polishPrompt = """
    You are KnowType, a macOS Chinese/English AI input method.
    Return JSON only with this shape: {"candidates":[{"text":"...","confidence":0.0,"reason":"..."}]}.
    For polish, rewriting is allowed because the user explicitly requested it.
    Preserve technical tokens such as API, JSON, FastAPI, iOS, macOS, InputMethodKit, snake_case, camelCase, and userID.
    """

    static func userPayload(for request: LLMRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
