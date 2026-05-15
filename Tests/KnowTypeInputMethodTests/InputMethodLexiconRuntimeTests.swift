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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeInputMethodLexiconRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
