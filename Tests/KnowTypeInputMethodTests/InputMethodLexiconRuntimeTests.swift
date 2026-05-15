import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputMethodLexiconRuntimeTests: XCTestCase {
    func testDefaultDirectoriesUseEnvironmentBeforeApplicationSupport() throws {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")
        let directories = InputMethodLexiconRuntime.defaultDirectories(
            environment: [
                InputMethodLexiconRuntime.environmentDirectoryKey: "/tmp/one",
                InputMethodLexiconRuntime.environmentDirectoriesKey: "/tmp/two:/tmp/one:/tmp/three"
            ],
            homeDirectory: home
        )

        XCTAssertEqual(directories.map(\.path), [
            "/tmp/one",
            "/tmp/two",
            "/tmp/three",
            "/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"
        ])
    }

    func testRuntimeLoadsAuthorizedDirectoryIntoTraditionalEngine() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ce shi ci\t测试词\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("user.tsv"))

        let engine = InputMethodLexiconRuntime(directories: [directory]).makeEngine()

        XCTAssertEqual(engine.candidates(for: "ceshici").first?.text, "测试词")
    }

    func testRuntimeSkipsMissingDirectoriesWithoutDiagnostics() {
        let runtime = InputMethodLexiconRuntime(
            directories: [URL(fileURLWithPath: "/tmp/knowtype-missing-\(UUID().uuidString)")]
        )
        let catalog = runtime.loadCatalog()

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertTrue(catalog.entries.isEmpty)
    }

    func testDefaultEngineReloadsRuntimeDirectoryContentsBetweenCalls() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let rawInput = "zizaoci"
        let customText = "自造词"

        let firstEngine = InputMethodLexiconRuntime.defaultEngine(
            environment: [:],
            homeDirectory: home
        )
        XCTAssertFalse(firstEngine.candidates(for: rawInput).contains { $0.text == customText })

        let lexiconDirectory = TraditionalInputLexiconDirectoryResolver
            .applicationSupportLexiconDirectory(homeDirectory: home)
        try FileManager.default.createDirectory(at: lexiconDirectory, withIntermediateDirectories: true)
        try Data("zi zao ci\t\(customText)\t0.995\n".utf8)
            .write(to: lexiconDirectory.appendingPathComponent("user.tsv"))

        let reloadedEngine = InputMethodLexiconRuntime.defaultEngine(
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(reloadedEngine.candidates(for: rawInput).first?.text, customText)
    }

    func testPipelineCanUseRuntimeLexiconEngine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ce shi ci\t测试词\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("user.tsv"))
        let engine = InputMethodLexiconRuntime(directories: [directory]).makeEngine()
        let pipeline = InputMethodPipeline(provider: nil, traditionalInputEngine: engine)
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "ceshici", locale: .zhCN)
        )

        XCTAssertEqual(response.prefixCandidates.first?.text, "测试词")
    }

    func testStaleCommitFallbackUsesRuntimeLexiconEngine() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ce shi ci\t测试词\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("user.tsv"))
        let engine = InputMethodLexiconRuntime(directories: [directory]).makeEngine()

        let result = InputSessionCommitPolicy.result(
            for: .space,
            rawInput: "ceshici",
            suggestion: nil,
            suggestionRawInput: nil,
            locale: .zhCN,
            traditionalInputEngine: engine
        )

        XCTAssertEqual(result, .commit("测试词"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeInputMethodLexiconRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
