import Foundation
import KnowTypeCore

enum ResponseNormalizer {
    static func normalizeText(_ text: String) throws -> LLMResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderError.invalidResponse("empty text content")
        }

        if let data = trimmed.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return response
        }

        if let data = trimmed.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data),
           let candidates = candidates(from: raw) {
            return LLMResponse(candidates: candidates)
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*0123456789.、) "))
            }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw ProviderError.invalidResponse("no candidates found")
        }

        return LLMResponse(candidates: lines.map { LLMCandidate(text: $0) })
    }

    static func candidates(from raw: Any) -> [LLMCandidate]? {
        if let array = raw as? [String] {
            return array.map { LLMCandidate(text: $0) }
        }
        if let array = raw as? [[String: Any]] {
            return array.compactMap(candidate(from:))
        }
        if let object = raw as? [String: Any] {
            if let candidates = object["candidates"] {
                return self.candidates(from: candidates)
            }
            if let text = object["text"] as? String {
                return [LLMCandidate(text: text)]
            }
        }
        return nil
    }

    static func string(at path: [String], in raw: Any) -> String? {
        var cursor = raw
        for part in path {
            if let index = Int(part), let array = cursor as? [Any], array.indices.contains(index) {
                cursor = array[index]
            } else if let object = cursor as? [String: Any], let next = object[part] {
                cursor = next
            } else {
                return nil
            }
        }
        return cursor as? String
    }

    static func value(at path: [String], in raw: Any) -> Any? {
        var cursor = raw
        for part in path {
            if let index = Int(part), let array = cursor as? [Any], array.indices.contains(index) {
                cursor = array[index]
            } else if let object = cursor as? [String: Any], let next = object[part] {
                cursor = next
            } else {
                return nil
            }
        }
        return cursor
    }

    private static func candidate(from object: [String: Any]) -> LLMCandidate? {
        guard let text = object["text"] as? String else {
            return nil
        }
        return LLMCandidate(
            text: text,
            confidence: object["confidence"] as? Double,
            reason: object["reason"] as? String
        )
    }
}
