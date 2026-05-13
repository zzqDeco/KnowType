import Foundation

public enum TextProtection {
    private static let protectedAppBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.dt.Xcode"
    ]
    private static let protectedAppBundleIDPrefixes = [
        "com.googlecode.iterm2"
    ]
    private static let unambiguousCommandNames: Set<String> = [
        "brew", "bun", "cargo", "cat", "cd", "chmod", "chown", "cp", "curl",
        "docker", "git", "grep", "kubectl", "ls", "mkdir",
        "mv", "node", "npm", "pnpm", "python", "python3", "rg", "rm",
        "ssh", "sudo", "swift", "touch", "vim", "yarn", "zsh"
    ]
    private static let goSubcommands: Set<String> = [
        "build", "clean", "doc", "env", "fmt", "generate", "get", "install",
        "list", "mod", "run", "test", "tool", "vet", "version", "work"
    ]
    private static let makeProseArguments: Set<String> = [
        "a", "an", "it", "me", "this", "that", "the", "these", "those", "us"
    ]
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
        if isProtectedAppBundleID(appBundleID) {
            return true
        }
        if containsLevelZeroProtectedRange(in: trimmed) {
            return true
        }
        if isURL(trimmed) {
            return true
        }
        if isEmail(trimmed) {
            return true
        }
        if isFilePath(trimmed) {
            return true
        }
        if isCommand(trimmed) {
            return true
        }
        if isCodeLike(trimmed) {
            return true
        }
        return false
    }

    public static func detectProtectedRanges(in text: String) -> [ProtectedRange] {
        let patterns: [(String, String)] = [
            (#"(?i)\b(?:[a-z][a-z0-9+.-]*://|www\.)[^\s]+"#, "url"),
            (#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "email"),
            (#"(?<!\S)(?:~?/|\./|\.\./)[^\s]+"#, "file_path"),
            (#"\b[A-Za-z]:[\\/][^\s]+"#, "file_path"),
            (#"\b[A-Z]{2,}\b"#, "acronym"),
            (#"\b[a-z]+_[a-zA-Z0-9_]+\b"#, "snake_case"),
            (#"\b[a-z]+[A-Z][a-zA-Z0-9]*\b"#, "camelCase"),
            (#"\b(?:FastAPI|InputMethodKit|macOS|iOS)\b"#, "technical_term")
        ]

        return patterns.flatMap { pattern, reason in
            ranges(matching: pattern, in: text, reason: reason)
        }.sorted { $0.start < $1.start }
    }

    private static func isProtectedAppBundleID(_ appBundleID: String?) -> Bool {
        guard let appBundleID else {
            return false
        }
        if protectedAppBundleIDs.contains(appBundleID) {
            return true
        }
        return protectedAppBundleIDPrefixes.contains { appBundleID.hasPrefix($0) }
    }

    private static func containsLevelZeroProtectedRange(in text: String) -> Bool {
        let levelZeroReasons: Set<String> = ["url", "email", "file_path", "snake_case", "camelCase"]
        return detectProtectedRanges(in: text).contains { levelZeroReasons.contains($0.reason) }
    }

    private static func isURL(_ text: String) -> Bool {
        text.range(of: #"(?i)^(?:[a-z][a-z0-9+.-]*://|www\.)\S+$"#, options: .regularExpression) != nil
    }

    private static func isEmail(_ text: String) -> Bool {
        text.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isFilePath(_ text: String) -> Bool {
        text.hasPrefix("/")
            || text.hasPrefix("~/")
            || text.hasPrefix("./")
            || text.hasPrefix("../")
            || text.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
            || text.hasPrefix("file://")
    }

    private static func isCommand(_ text: String) -> Bool {
        if text.hasPrefix("$ ") || text.hasPrefix("> ") {
            return true
        }
        if hasCommandOperator(in: text) {
            return true
        }
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let firstToken = tokens.first else {
            return false
        }
        if unambiguousCommandNames.contains(firstToken) {
            return true
        }
        return isAmbiguousCommand(tokens)
    }

    private static func isCodeLike(_ text: String) -> Bool {
        if text.contains(";") || text.contains("{") || text.contains("}") || text.contains("=>") {
            return true
        }
        if text.range(
            of: #"^(?:\s*)?(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*(?::|=)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if text.range(
            of: #"^(?:\s*)?(?:func|class|struct|enum)\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*[({:]|\s*$)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if text.range(
            of: #"^(?:\s*)?import\s+(?:[A-Z][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.]+)(?:\s*$|;)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if text.range(
            of: #"^[A-Za-z_][A-Za-z0-9_.]*\s*(?:=|\+=|-=|\*=|/=|==|!=|<=|>=)\s*\S+"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if text.range(of: #"^[A-Za-z_][A-Za-z0-9_]*\("#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$"#, options: .regularExpression) != nil {
            return true
        }
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        if tokens.count == 1 {
            return text.range(of: #"^[a-z]+_[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
                || text.range(of: #"^[a-z]+[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
        }
        return false
    }

    private static func hasCommandOperator(in text: String) -> Bool {
        let operatorPatterns = [
            #"(^|\s)(?:&&|\|\|)\s*"#,
            #"\s\|\s"#,
            #"\s(?:[0-9]?>|>>|<|<<|&>)\s*\S+"#
        ]
        guard operatorPatterns.contains(where: {
            text.range(of: $0, options: .regularExpression) != nil
        }) else {
            return false
        }

        let commandPrefix = text.split(
            maxSplits: 1,
            whereSeparator: { character in
                character == "|" || character == "<" || character == ">" || character == "&"
            }
        ).first.map(String.init) ?? text
        return isCommand(commandPrefix.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isAmbiguousCommand(_ tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }
        switch tokens[0] {
        case "go":
            return goSubcommands.contains(tokens[1])
        case "make":
            let target = tokens[1]
            return target.hasPrefix("-")
                || target.contains("=")
                || target.contains(":")
                || target.contains("_")
                || (target.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
                    && !makeProseArguments.contains(target.lowercased()))
        default:
            return false
        }
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
