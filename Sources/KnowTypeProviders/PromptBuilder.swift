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
    The user message is a JSON object. Read lockedPrefix, rawInput, candidateHints, locale, appContext, maxCandidates, and lengthLevel.
    lockedPrefix is text the user has already confirmed. candidateHints are only current-page Rime suggestions; they are not selected text.
    Rules:
    - If lockedPrefix is present, text must be only the suffix after lockedPrefix. Do not include, paraphrase, translate, rewrite, or polish lockedPrefix.
    - If lockedPrefix is absent, text must be a complete commit-ready recommendation inferred from rawInput, context, highlighted hint, and candidateHints.
    - candidateHints are hints only. Do not default mechanically to the first hint, and do not need to copy any hint exactly.
    - Prefer one concise, immediately useful Chinese recommendation in the same intent as rawInput and locale.
    - Empty candidates are allowed only when lockedPrefix/candidateHints are unsafe, impossible, or nonsensical.
    - Preserve English technical tokens exactly, including API, JSON, macOS, InputMethodKit, snake_case, and camelCase.
    Good: lockedPrefix="我觉得这个方案" text="还可以再细化一下。"
    Good: lockedPrefix=null rawInput="zhege api de yanchi" candidateHints=[{"text":"这个 API 的延迟"},{"text":"这个 PR 的问题"}] text="这个 API 的延迟主要卡在网络和序列化两段。"
    Good: lockedPrefix=null rawInput="this approach" candidateHints=[{"text":"This approach"}] text="This approach keeps the hot path simple."
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
