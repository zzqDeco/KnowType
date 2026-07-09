import Foundation
import KnowTypeCore
import KnowTypeInputMethod

struct DemoOptions {
    var rawInput: String = ""
    var locale: KnowTypeLocale = .mixed
    var action: InputAction = .tab
}

@main
struct KnowTypeDemo {
    static func main() async {
        do {
            let options = try parseOptions(CommandLine.arguments.dropFirst())
            guard !options.rawInput.isEmpty else {
                printUsage()
                Foundation.exit(2)
            }

            let session = InputSessionController()
            let suggestion = await session.update(rawInput: options.rawInput, locale: options.locale)
            let panel = await session.candidatePanelViewModel
            let rendered = CandidatePanelRenderer(locale: options.locale).render(panel)
            let commit = await session.handle(action: options.action)

            print("KnowType Demo")
            print("Input: \(options.rawInput)")
            print("Latency: \(suggestion.latencyMs)ms")
            print("")
            printRows(rendered.rows)
            print("")
            print("Action: \(describe(options.action))")
            print("Result: \(describe(commit))")
        } catch {
            fputs("knowtype-demo: \(error)\n", stderr)
            printUsage()
            Foundation.exit(2)
        }
    }

    private static func parseOptions(_ arguments: ArraySlice<String>) throws -> DemoOptions {
        var options = DemoOptions()
        var iterator = arguments.makeIterator()
        var rawParts: [String] = []

        while let argument = iterator.next() {
            switch argument {
            case "--locale":
                guard let value = iterator.next(), let locale = KnowTypeLocale(rawValue: value) else {
                    throw DemoError.invalidArgument("--locale expects zh-CN, en-US, or mixed")
                }
                options.locale = locale
            case "--action":
                guard let value = iterator.next(), let action = parseAction(value) else {
                    throw DemoError.invalidArgument("--action expects space, tab, optionN, or polish")
                }
                options.action = action
            case "--help", "-h":
                printUsage()
                Foundation.exit(0)
            default:
                rawParts.append(argument)
            }
        }

        options.rawInput = rawParts.joined(separator: " ")
        return options
    }

    private static func parseAction(_ value: String) -> InputAction? {
        switch value.lowercased() {
        case "space":
            return .space
        case "tab":
            return .tab
        case "polish", "optionr", "option-r":
            return .optionR
        default:
            if value.lowercased().hasPrefix("option"),
               let number = Int(value.dropFirst("option".count)) {
                return .optionNumber(number)
            }
            return nil
        }
    }

    private static func printRows(_ rows: [CandidatePanelRenderRow]) {
        for row in rows {
            let shortcut = row.shortcutLabel.map { "\($0) " } ?? ""
            print("  \(shortcut)\(row.text)")
        }
    }

    private static func describe(_ action: InputAction) -> String {
        switch action {
        case .space:
            return "Space"
        case .tab:
            return "Tab"
        case .optionNumber(let number):
            return "Option+\(number)"
        case .optionR:
            return "Option+R"
        case .toggleSymbolMode:
            return "Option+."
        case .toggleTextMode:
            return "Option+/"
        case .toggleSymbolWidth:
            return "Shift+Space"
        case .commitRaw:
            return "Return"
        }
    }

    private static func describe(_ result: InputCommitResult) -> String {
        switch result {
        case .commit(let text):
            return "commit \"\(text)\""
        case .polishRequested(let text):
            return "polish requested for \"\(text)\""
        case .noAction:
            return "no action"
        }
    }

    private static func printUsage() {
        print("""
        Usage:
          knowtype-demo [--locale zh-CN|en-US|mixed] [--action space|tab|optionN|polish] <raw input>

        Examples:
          swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
          swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
          swift run knowtype-demo --locale en-US --action tab I thikn this approch
        """)
    }
}

enum DemoError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case .invalidArgument(let message):
            return message
        }
    }
}
