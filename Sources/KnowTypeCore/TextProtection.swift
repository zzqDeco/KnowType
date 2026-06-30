import Foundation

private struct TextProtectionRegexPattern: @unchecked Sendable {
    let regex: NSRegularExpression
    let reason: String

    init(_ pattern: String, reason: String) {
        self.regex = try! NSRegularExpression(pattern: pattern, options: [])
        self.reason = reason
    }
}

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
        "docker": ["build", "compose", "exec", "images", "inspect", "login", "logs", "ps", "pull", "push", "rm", "run", "start", "stop"],
        "git": ["add", "branch", "checkout", "clone", "commit", "config", "diff", "fetch", "log", "merge", "pull", "push", "rebase", "restore", "stash", "status", "switch"],
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
        "cd", "echo", "env", "export", "pwd", "source", "unset"
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
        "css": "CSS",
        "json": "JSON",
        "fastapi": "FastAPI",
        "gpt": "GPT",
        "llm": "LLM",
        "ios": "iOS",
        "macos": "macOS",
        "npm": "npm",
        "sdk": "SDK",
        "ssh": "SSH",
        "inputmethodkit": "InputMethodKit"
    ]
    private static let protectedRangePatterns: [TextProtectionRegexPattern] = [
        TextProtectionRegexPattern(#"(?i)\b(?:[a-z][a-z0-9+.-]*://|www\.)[^\s]+"#, reason: "url"),
        TextProtectionRegexPattern(#"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|org|net|edu|gov|io|ai|app|dev|co|us|uk|cn|jp|de|fr|me|info|biz|site|tech)(?::\d+)?(?:/[^\s]*)?"#, reason: "url"),
        TextProtectionRegexPattern(#"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}(?::\d+)?(?:/[^\s]*)?"#, reason: "url"),
        TextProtectionRegexPattern(#"(?i)\blocalhost(?::\d+)?(?:/[^\s]*)?"#, reason: "url"),
        TextProtectionRegexPattern(#"\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?::\d+)?(?:/[^\s]*)?"#, reason: "url"),
        TextProtectionRegexPattern(#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, reason: "email"),
        TextProtectionRegexPattern(#"(?<!\S)(?:~?/|\./|\.\./)[^\s]+"#, reason: "file_path"),
        TextProtectionRegexPattern(#"\b[A-Za-z]:[\\/][^\s]+"#, reason: "file_path"),
        TextProtectionRegexPattern(#"\b[A-Z]{2,}\b"#, reason: "acronym"),
        TextProtectionRegexPattern(#"\b[a-z]+_[a-zA-Z0-9_]+\b"#, reason: "snake_case"),
        TextProtectionRegexPattern(#"\b[a-z]+[A-Z][a-zA-Z0-9]*\b"#, reason: "camelCase"),
        TextProtectionRegexPattern(#"\b(?:FastAPI|InputMethodKit|macOS|iOS)\b"#, reason: "technical_term")
    ]
    private static let secretLikePatterns: [TextProtectionRegexPattern] = [
        TextProtectionRegexPattern(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, reason: "secret_private_key"),
        TextProtectionRegexPattern(#"(?i)(?:^|[^A-Za-z0-9_])['"]?Authorization['"]?\s*:\s*['"]?\s*(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}"#, reason: "secret_authorization_header"),
        TextProtectionRegexPattern(#"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{16,}\b"#, reason: "secret_openai_key"),
        TextProtectionRegexPattern(#"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"#, reason: "secret_github_token"),
        TextProtectionRegexPattern(#"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#, reason: "secret_github_token"),
        TextProtectionRegexPattern(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, reason: "secret_aws_key"),
        TextProtectionRegexPattern(#"\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#, reason: "secret_jwt"),
        TextProtectionRegexPattern(#"(?i)(?:^|[^A-Za-z0-9_])['"]?(?:api[_-]?key|token|access[_-]?token|refresh[_-]?token|auth[_-]?token|password|passwd|secret|client[_-]?secret|private[_-]?key)['"]?\s*[:=]\s*['"]?[^'"\s]{4,}"#, reason: "secret_assignment"),
        TextProtectionRegexPattern(#"(?i)[?&](?:api[_-]?key|key|token|access[_-]?token|password|secret|client[_-]?secret)=[^&#\s]{4,}"#, reason: "secret_url_query")
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
        protectedRangePatterns.flatMap { pattern in
            ranges(matching: pattern, in: text)
        }.sorted { $0.start < $1.start }
    }

    public static func containsSecretLikeContent(_ text: String) -> Bool {
        !detectSecretLikeRanges(in: text).isEmpty
    }

    public static func detectSecretLikeRanges(in text: String) -> [ProtectedRange] {
        secretLikePatterns.flatMap { pattern in
            ranges(matching: pattern, in: text)
        }.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.length > rhs.length
            }
            return lhs.start < rhs.start
        }
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
            || text.range(
                of: #"(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|org|net|edu|gov|io|ai|app|dev|co|us|uk|cn|jp|de|fr|me|info|biz|site|tech)(?::\d+)?(?:/[^\s]*)?$"#,
                options: .regularExpression
            ) != nil
            || text.range(
                of: #"(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}(?::\d+)?(?:/[^\s]*)?$"#,
                options: .regularExpression
            ) != nil
            || text.range(
                of: #"(?i)^localhost(?::\d+)?(?:/[^\s]*)?$"#,
                options: .regularExpression
            ) != nil
            || text.range(
                of: #"^(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?::\d+)?(?:/[^\s]*)?$"#,
                options: .regularExpression
            ) != nil
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
        let tokens = commandTokens(from: text)
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
        guard let operatorRange = text.range(
            of: #"(?:&&|\|\||\||[0-9]?>|>>|<|<<|&>)"#,
            options: .regularExpression
        ) else {
            return false
        }

        let commandPrefix = String(text[..<operatorRange.lowerBound])
        return isCommandShape(commandPrefix.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isCommandInvocation(firstToken: String, tokens: [String]) -> Bool {
        let command = normalizedCommandName(firstToken)
        guard let command else {
            return false
        }

        if tokens.count == 1 {
            return command == "cd" || command == "env" || command == "pwd"
        }

        let arguments = Array(tokens.dropFirst())
        if command == "sudo" {
            let sudoArguments = argumentsAfterSudoOptions(arguments)
            guard let wrappedCommand = sudoArguments.first else {
                return false
            }
            return isCommandInvocation(firstToken: wrappedCommand, tokens: sudoArguments)
        }
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
            return arguments.contains { argument in
                isCommandPathArgument(argument) || isBasenameFileArgument(argument)
            }
        }
        if networkCommandNames.contains(command) {
            return arguments.contains(where: isURLLikeArgument)
                || arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isHostLikeArgument)
        }
        if executableCommandNames.contains(command) {
            if let wrappedCommand = arguments.first,
               isCommandInvocation(firstToken: wrappedCommand, tokens: arguments) {
                return true
            }
            return arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isScriptFileArgument)
                || commandSubcommands[arguments[0].lowercased()] != nil
        }
        return false
    }

    private static func commandTokens(from text: String) -> [String] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return Array(tokens.drop(while: isEnvironmentAssignment))
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

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        return stripped.range(
            of: #"^[A-Za-z_][A-Za-z0-9_]*=.+"#,
            options: .regularExpression
        ) != nil
    }

    private static func argumentsAfterSudoOptions(_ arguments: [String]) -> [String] {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index].trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
            if argument == "--" {
                index += 1
                break
            }
            guard argument.hasPrefix("-"), argument.count > 1 else {
                break
            }

            index += 1
            if sudoOptionTakesValue(argument), index < arguments.count {
                index += 1
            }
        }
        return Array(arguments.dropFirst(index))
    }

    private static func sudoOptionTakesValue(_ option: String) -> Bool {
        let optionName = option.split(separator: "=", maxSplits: 1).first.map(String.init) ?? option
        let optionsWithValue: Set<String> = [
            "-C", "--close-from",
            "-D", "--chdir",
            "-g", "--group",
            "-h", "--host",
            "-p", "--prompt",
            "-R", "--chroot",
            "-r", "--role",
            "-t", "--type",
            "-u", "--user"
        ]
        return optionsWithValue.contains(optionName) && !option.contains("=")
    }

    private static func isCommandFlagOrAssignment(_ argument: String) -> Bool {
        argument.hasPrefix("-")
            || argument.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
    }

    private static func isShellBuiltinInvocation(command: String, arguments: [String]) -> Bool {
        switch command {
        case "cd", "pwd":
            return true
        case "echo":
            return arguments.contains { argument in
                argument.hasPrefix("$") || argument.contains("$")
            }
        case "env":
            return arguments.isEmpty || arguments.contains(where: isCommandFlagOrAssignment)
        case "export":
            return arguments.contains(where: isCommandFlagOrAssignment)
        case "source":
            return arguments.contains(where: isCommandPathArgument)
                || arguments.contains(where: isScriptFileArgument)
                || arguments.contains(where: isDotfileArgument)
        case "unset":
            return arguments.contains { argument in
                argument.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
            }
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
            of: #"^(?:[A-Za-z0-9_][A-Za-z0-9_.-]*@)?(?:localhost|[A-Za-z0-9][A-Za-z0-9-]*|[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+|\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isBasenameFileArgument(_ argument: String) -> Bool {
        let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        if isDotfileArgument(trimmed) {
            return true
        }
        return trimmed.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9][A-Za-z0-9_-]*)+$"#,
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
        return trimmed.range(of: #"^(?:(?:~|\.|\.\.)/)?[A-Za-z0-9][A-Za-z0-9_.-]*\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isDotfileArgument(_ argument: String) -> Bool {
        let trimmed = argument.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        return trimmed.range(of: #"^(?:(?:~|\.|\.\.)/)?\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$"#, options: .regularExpression) != nil
    }

    private static func ranges(matching pattern: TextProtectionRegexPattern, in text: String) -> [ProtectedRange] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return ProtectedRange(start: start, length: length, reason: pattern.reason)
        }
    }
}
