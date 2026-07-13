import Foundation
import KnowTypeCore

enum StructuredResponseNormalizer {
    static func normalizeText(
        _ text: String,
        task: LLMTask,
        diagnostics: [String] = []
    ) throws -> LLMResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw structuredDecodeError("empty text content")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw structuredDecodeError("text content is not UTF-8")
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw structuredDecodeError("invalid JSON object")
        }
        return try normalizeValue(raw, task: task, diagnostics: diagnostics)
    }

    static func normalizeValue(
        _ raw: Any,
        task: LLMTask,
        diagnostics: [String] = [],
        allowCandidateArrayRoot: Bool = false
    ) throws -> LLMResponse {
        if allowCandidateArrayRoot,
           task != .contextDigest,
           let rawCandidates = raw as? [Any] {
            let candidates = try rawCandidates.map(candidate(from:))
            return LLMResponse(candidates: candidates, diagnostics: diagnostics)
        }
        guard let object = raw as? [String: Any] else {
            throw structuredDecodeError("top-level value is not an object")
        }

        switch task {
        case .contextDigest:
            guard object.keys.allSatisfy({ $0 == "markdown" }) else {
                throw structuredDecodeError("unexpected contextDigest fields")
            }
            guard let markdown = object["markdown"] as? String else {
                throw structuredDecodeError("missing markdown")
            }
            return LLMResponse(
                candidates: [LLMCandidate(text: markdown)],
                diagnostics: diagnostics
            )
        case .correction, .continuation:
            guard object.keys.allSatisfy({ $0 == "candidates" }) else {
                throw structuredDecodeError("unexpected candidate response fields")
            }
            guard let rawCandidates = object["candidates"] as? [Any] else {
                throw structuredDecodeError("missing candidates")
            }
            let candidates = try rawCandidates.map(candidate(from:))
            return LLMResponse(candidates: candidates, diagnostics: diagnostics)
        }
    }

    private static func candidate(from raw: Any) throws -> LLMCandidate {
        guard let object = raw as? [String: Any] else {
            throw structuredDecodeError("candidate is not an object")
        }
        guard object.keys.allSatisfy({ $0 == "text" || $0 == "confidence" || $0 == "reason" }) else {
            throw structuredDecodeError("unexpected candidate fields")
        }
        guard let text = object["text"] as? String else {
            throw structuredDecodeError("candidate text is missing or not a string")
        }

        let confidence: Double?
        if let value = object["confidence"] as? Double {
            confidence = value
        } else if let value = object["confidence"] as? Int {
            confidence = Double(value)
        } else if object["confidence"] == nil {
            confidence = nil
        } else {
            throw structuredDecodeError("candidate confidence is not a number")
        }

        let reason: String?
        if let value = object["reason"] as? String {
            reason = value
        } else if object["reason"] == nil {
            reason = nil
        } else {
            throw structuredDecodeError("candidate reason is not a string")
        }

        return LLMCandidate(text: text, confidence: confidence, reason: reason)
    }

    private static func structuredDecodeError(_ message: String) -> ProviderError {
        ProviderError.invalidResponse("structured_decode_error: \(message)")
    }
}
