import Foundation

public enum TextProtection {
    private static let protectedAppBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.dt.Xcode"
    ]
    private static let protectedAppBundleIDPrefixes = [
        "com.googlecode.iterm2"
    ]
    private static let commandSubcommands: [String: Set<String>] = [
        "brew": ["bundle", "cleanup", "doctor", "info", "install", "list", "search", "services", "tap", "uninstall", "update", "upgrade"],
        "bun": ["add", "build", "create", "install", "remove", "run", "test"],
        "cargo": ["add", "build", "check", "clean", "doc", "fmt", "install", "new", "run", "test", "update"],
        "docker": ["build", "compose", "exec", "images", "inspect", "logs", "ps", "pull", "push", "rm", "run", "start", "stop"],
        "git": ["add", "branch", "checkout", "clone", "commit", "diff", "fetch", "log", "merge", "pull", "push", "rebase", "restore", "status", "switch"],
        "go": ["build", "clean", "doc", "env", "fmt", "generate", "get", "install", "list", "mod", "run", "test", "tool", "vet", "version", "work"],
        "kubectl": ["apply", "config", "create", "delete", "describe", "edit", "exec", "get", "logs", "port-forward", "rollout", "scale"],
        "make": ["build", "check", "clean", "install", "lint", "release", "run", "test"],
        "node": ["--check", "--eval", "--print"],
        "npm": ["add", "audit", "build", "ci", "create", "exec", "install", "link", "publish", "remove", "run", "test", "update"],
        "pnpm": ["add", "audit", "build", "create", "exec", "install", "link", "publish", "remove", "run", "test", "update"],
        "swift": ["build", "format", "package", "run", "test"],
        "yarn": ["add", "build", "create", "install", "remove", "run", "test", "upgrade"]
    ]
    private static let shellBuiltins: Set<String> = [
        "cd", "export", "source"
    ]
    private static let pathCommandNames: Set<String> = [
        "cat", "chmod", "chown", "cp", "grep", "ls", "mkdir", "mv", "rg", "rm", "touch", "vim"
    ]
    private static let networkCommandNames: Set<String> = [
        "curl", "ssh"
    ]
    private static let executableCommandNames: Set<String> = [
        "node", "python", "python3", "sudo", "zsh"
    ]
    private static let scriptFileExtensions: Set<String> = [
        "js", "mjs", "py", "rb", "sh", "swift", "ts"
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
        let levelZeroReasons: Set<String> = ["url", "email", "file_path"]
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
        if text.hasPrefix("$ ") {
            return isCommandShape(String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if text.hasPrefix("> ") {
            return isCommandShape(String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return isCommandShape(text)
    }

    private static func isCommandShape(_ text: String) -> Bool {
        if hasCommandOperator(in: text) {
            return true
        }
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let firstToken = tokens.first else {
            return false
        }
        return isCommandInvocation(firstToken: firstToken, tokens: tokens)
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
        return isCommandShape(commandPrefix.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isCommandInvocation(firstToken: String, tokens: [String]) -> Bool {
        let command = normalizedCommandName(firstToken)
        guard let command else {
            return false
        }

        if tokens.count == 1 {
            return command == "cd"
        }

        let arguments = Array(tokens.dropFirst())
        if shellBuiltins.contains(command) {
            return isShellBuiltinInvocation(command: command, arguments: arguments)
        }
        if arguments.contains(where: isCommandFlagOrAssignment) {
            return true
        }
        if let subcommands = commandSubcommands[command],
           subcommands.contains(arguments[0].lowercased()) {
            return true
        }
        if pathCommandNames.contains(command) {
            return arguments.contains(where: isCommandPathArgument)
        }
        if networkCommandNames.contains(command) {
            return arguments.contains(where: isURLLikeArgument)
                || arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isHostLikeArgument)
        }
        if executableCommandNames.contains(command) {
            return arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isScriptFileArgument)
                || commandSubcommands[arguments[0].lowercased()] != nil
        }
        return false
    }

    private static func normalizedCommandName(_ token: String) -> String? {
        let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        let knownCommands = Set(commandSubcommands.keys)
            .union(shellBuiltins)
            .union(pathCommandNames)
            .union(networkCommandNames)
            .union(executableCommandNames)
        guard knownCommands.contains(stripped) else {
            return nil
        }
        return stripped
    }

    private static func isCommandFlagOrAssignment(_ argument: String) -> Bool {
        argument.hasPrefix("-")
            || argument.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
    }

    private static func isShellBuiltinInvocation(command: String, arguments: [String]) -> Bool {
        switch command {
        case "cd":
            return true
        case "export":
            return arguments.contains(where: isCommandFlagOrAssignment)
        case "source":
            return arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isScriptFileArgument)
                || arguments.contains(where: isDotfileArgument)
        default:
            return false
        }
    }

    private static func isCommandPathArgument(_ argument: String) -> Bool {
        argument.hasPrefix("/")
            || argument.hasPrefix("~/")
            || argument.hasPrefix("./")
            || argument.hasPrefix("../")
            || argument.hasPrefix("file://")
            || argument.contains("/")
            || argument.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    private static func isURLLikeArgument(_ argument: String) -> Bool {
        argument.range(of: #"(?i)^(?:[a-z][a-z0-9+.-]*://|www\.)\S+$"#, options: .regularExpression) != nil
    }

    private static func isHostLikeArgument(_ argument: String) -> Bool {
        let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        return trimmed.range(
            of: #"^(?:[A-Za-z0-9_][A-Za-z0-9_.-]*@)?(?:localhost|[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+|[A-Za-z0-9][A-Za-z0-9-]*-[A-Za-z0-9][A-Za-z0-9-]*|\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isScriptFileArgument(_ argument: String) -> Bool {
        let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        guard let extensionStart = trimmed.lastIndex(of: "."),
              extensionStart != trimmed.startIndex else {
            return false
        }
        let fileExtension = String(trimmed[trimmed.index(after: extensionStart)...]).lowercased()
        guard scriptFileExtensions.contains(fileExtension) else {
            return false
        }
        return trimmed.range(of: #"^[A-Za-z0-9_.~/-]+\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isDotfileArgument(_ argument: String) -> Bool {
        let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        return trimmed.range(of: #"^(?:\.|~?/|\.?/)?\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
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
