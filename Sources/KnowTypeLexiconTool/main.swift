import Foundation
import KnowTypeCore

@main
struct KnowTypeLexiconTool {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return
        }

        guard arguments.first == "install" else {
            throw ManagedLexiconPackInstallerError.unknownPack(arguments.first ?? "")
        }

        var packID = ManagedLexiconPacks.recommended.id
        var force = false
        var directory = TraditionalInputLexiconDirectoryResolver.applicationSupportLexiconDirectory()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--force":
                force = true
            case "--directory":
                index += 1
                guard index < arguments.count else {
                    throw ToolError.missingValue("--directory")
                }
                directory = URL(fileURLWithPath: arguments[index]).standardizedFileURL
            default:
                if argument.hasPrefix("-") {
                    throw ToolError.unknownArgument(argument)
                }
                packID = argument
            }
            index += 1
        }

        guard let pack = ManagedLexiconPacks.pack(id: packID) else {
            throw ManagedLexiconPackInstallerError.unknownPack(packID)
        }

        let metadata = try await ManagedLexiconPackInstaller().install(
            pack,
            destinationDirectory: directory,
            force: force
        )
        print("Installed \(metadata.displayName)")
        print("Directory: \(directory.path)")
        print("Entries: \(metadata.entryCount)")
        print("License: \(metadata.licenseName)")
        print("Source: \(metadata.sourceURL.absoluteString)")
    }

    private static func printUsage() {
        print(
            """
            Usage: knowtype-lexicon-tool install [pack-id] [--directory PATH] [--force]

            Installs a managed KnowType lexicon pack.

            Packs:
              rime-pinyin-simp  Rime Pinyin Simplified dictionary (Apache-2.0)

            Options:
              --directory PATH  Install into a custom lexicon directory
              --force           Replace an existing pack output file
              -h, --help        Show this help
            """
        )
    }
}

private enum ToolError: Error, LocalizedError, Equatable {
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(argument):
            return "Missing value for \(argument)"
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)"
        }
    }
}
