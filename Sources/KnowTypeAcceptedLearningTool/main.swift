import Foundation
import KnowTypeAI

private enum ExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 2
}

@main
struct KnowTypeAcceptedLearningTool {
    static func main() {
        do {
            let result = try run(arguments: Array(CommandLine.arguments.dropFirst()))
            if result.exitCode != .ok {
                fputs(result.output, stderr)
                Foundation.exit(result.exitCode.rawValue)
            }
            print(result.output, terminator: result.output.hasSuffix("\n") ? "" : "\n")
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(ExitCode.failure.rawValue)
        }
    }

    private static func run(arguments: [String]) throws -> CommandResult {
        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            return CommandResult(output: usage(), exitCode: .ok)
        }

        var values = arguments
        let command = values.removeFirst()
        let json = consumeFlag("--json", from: &values)
        let yes = consumeFlag("--yes", from: &values)
        guard values.isEmpty else {
            return CommandResult(output: "error: unknown argument: \(values[0])\n\(usage())", exitCode: .usage)
        }

        let maintenance = AIAcceptedLearningMaintenance()
        switch command {
        case "status":
            let status = maintenance.status()
            return CommandResult(output: render(status, json: json), exitCode: .ok)
        case "rebuild":
            let status = try maintenance.rebuild()
            return CommandResult(output: render(status, json: json), exitCode: .ok)
        case "clear":
            guard yes else {
                let message = "error: clear requires --yes; accepted AI learning history was not deleted\n"
                let output = json ? render(maintenance.status(), json: true) : message + renderPlain(maintenance.status())
                return CommandResult(output: output, exitCode: .usage)
            }
            let status = try maintenance.clear(confirm: true)
            return CommandResult(output: render(status, json: json), exitCode: .ok)
        default:
            return CommandResult(output: "error: unknown command: \(command)\n\(usage())", exitCode: .usage)
        }
    }

    private static func consumeFlag(_ flag: String, from values: inout [String]) -> Bool {
        guard let index = values.firstIndex(of: flag) else {
            return false
        }
        values.remove(at: index)
        return true
    }

    private static func render(_ status: AIAcceptedLearningMaintenanceStatus, json: Bool) -> String {
        json ? renderJSON(status) : renderPlain(status)
    }

    private static func renderJSON(_ status: AIAcceptedLearningMaintenanceStatus) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(status),
              let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text + "\n"
    }

    private static func renderPlain(_ status: AIAcceptedLearningMaintenanceStatus) -> String {
        let action = status.action.map { "Action: \($0)\n\n" } ?? ""
        let historyHash = status.history.historyHash.map(shortHash(_:)) ?? "none"
        let summaryHash = status.summary.historyHash.map(shortHash(_:)) ?? "none"
        let summaryState = status.summary.isCurrentWithHistory ? "current" : "stale"
        let lexicalState = status.lexicalProfile.containsAcceptedAISummary ? "yes" : "no"
        let warnings = status.warnings.isEmpty
            ? "Warnings: none"
            : "Warnings: \(status.warnings.joined(separator: ", "))"
        return """
        \(action)KnowType accepted AI learning
        History: \(status.history.exists ? "exists" : "missing"), records=\(status.history.recordCount), hash=\(historyHash), mtime=\(status.history.mtime ?? "none")
        Summary: \(status.summary.exists ? "exists" : "missing"), state=\(summaryState), accepted=\(status.summary.acceptedCount), terms=\(status.summary.termCount), commits=\(status.summary.recentCommitCount), hash=\(summaryHash), generatedAt=\(status.summary.generatedAt ?? "none")
        Mirror: \(status.mirror.exists ? "exists" : "missing"), mtime=\(status.mirror.mtime ?? "none")
        LEXICAL_PROFILE.md accepted-ai-summary: \(lexicalState), mtime=\(status.lexicalProfile.mtime ?? "none")
        \(warnings)
        Commands:
          ./scripts/accepted-learning.sh status
          ./scripts/accepted-learning.sh rebuild
          ./scripts/accepted-learning.sh clear --yes
        """
    }

    private static func shortHash(_ hash: String) -> String {
        String(hash.prefix(8))
    }

    private static func usage() -> String {
        """
        Usage:
          knowtype-accepted-learning-tool status [--json]
          knowtype-accepted-learning-tool rebuild [--json]
          knowtype-accepted-learning-tool clear --yes [--json]

        Maintains KnowType accepted AI learning history, summary, and readable mirror.
        The clear command deletes accepted-learning files and scrubs accepted-AI
        lexical-profile context. It never deletes Rime, provider, Keychain,
        ENV.md, or CORRECTION.md data.
        """
    }
}

private struct CommandResult {
    var output: String
    var exitCode: ExitCode
}
