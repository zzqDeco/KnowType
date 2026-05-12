import Foundation

public enum TextProtection {
    private static let protectedTokens: [String: String] = [
        "api": "API",
        "json": "JSON",
        "fastapi": "FastAPI",
        "ios": "iOS",
        "macos": "macOS",
        "inputmethodkit": "InputMethodKit"
    ]

    public static func canonicalTechnicalToken(_ token: String) -> String? {
        protectedTokens[token.lowercased()]
    }

    public static func requiresNoCorrection(_ text: String, appBundleID: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if appBundleID == "com.apple.Terminal" || appBundleID == "com.googlecode.iterm2" {
            return true
        }
        if trimmed.contains("://") || trimmed.hasPrefix("www.") {
            return true
        }
        if trimmed.contains("@"), trimmed.contains(".") {
            return true
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }
        if trimmed.contains(";") || trimmed.contains("{") || trimmed.contains("}") || trimmed.contains("=>") {
            return true
        }
        return false
    }

    public static func detectProtectedRanges(in text: String) -> [ProtectedRange] {
        let patterns: [(String, String)] = [
            (#"https?://[^\s]+"#, "url"),
            (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "email"),
            (#"\b[A-Z]{2,}\b"#, "acronym"),
            (#"\b[a-z]+_[a-zA-Z0-9_]+\b"#, "snake_case"),
            (#"\b[a-z]+[A-Z][a-zA-Z0-9]*\b"#, "camelCase"),
            (#"\b(?:FastAPI|InputMethodKit|macOS|iOS)\b"#, "technical_term")
        ]

        return patterns.flatMap { pattern, reason in
            ranges(matching: pattern, in: text, reason: reason)
        }.sorted { $0.start < $1.start }
    }

    private static func ranges(matching pattern: String, in text: String, reason: String) -> [ProtectedRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return ProtectedRange(start: start, length: length, reason: reason)
        }
    }
}
