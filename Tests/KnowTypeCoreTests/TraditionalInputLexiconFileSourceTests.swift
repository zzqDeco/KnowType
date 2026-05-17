import Foundation
import XCTest
@testable import KnowTypeCore

final class TraditionalInputLexiconFileSourceTests: XCTestCase {
    func testFormatInferenceIsCaseInsensitive() {
        XCTAssertEqual(TraditionalInputLexiconFileSource.format(for: URL(fileURLWithPath: "words.JSON")), .json)
        XCTAssertEqual(TraditionalInputLexiconFileSource.format(for: URL(fileURLWithPath: "words.tsv")), .tsv)
        XCTAssertNil(TraditionalInputLexiconFileSource.format(for: URL(fileURLWithPath: "words.txt")))
    }

    func testLoadFilesBuildsCatalogFromJSONAndTSVFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let jsonURL = directory.appendingPathComponent("01-places.json")
        let tsvURL = directory.appendingPathComponent("02-products.tsv")
        try Data("""
        [{ "pinyin": ["xi", "an"], "outputs": [{ "text": "西安", "confidence": 0.995 }] }]
        """.utf8).write(to: jsonURL)
        try Data("ce shi ci\t测试词\t0.91\n".utf8).write(to: tsvURL)

        let catalog = TraditionalInputLexiconFileSource().loadFiles([jsonURL, tsvURL])
        let engine = catalog.makeEngine()

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertEqual(catalog.entries.count, 2)
        XCTAssertEqual(engine.candidates(for: "xian").first?.text, "西安")
        XCTAssertEqual(engine.candidates(for: "ceshici").first?.text, "测试词")
    }

    func testLoadFilesKeepsValidEntriesAndReportsUnsupportedOrInvalidFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let validURL = directory.appendingPathComponent("valid.tsv")
        let invalidURL = directory.appendingPathComponent("invalid.tsv")
        let unsupportedURL = directory.appendingPathComponent("notes.txt")
        try Data("ce shi ci\t测试词\t0.91\n".utf8).write(to: validURL)
        try Data("bad\trow\t0.9\textra\n".utf8).write(to: invalidURL)
        try Data("ignored\n".utf8).write(to: unsupportedURL)

        let catalog = TraditionalInputLexiconFileSource().loadFiles([
            validURL,
            invalidURL,
            unsupportedURL
        ])

        XCTAssertEqual(catalog.entries.map(\.outputs.first?.text), ["测试词"])
        XCTAssertEqual(catalog.diagnostics, [
            TraditionalInputLexiconDiagnostic(
                resourceID: "notes.txt",
                error: .unsupportedFormat("txt")
            ),
            TraditionalInputLexiconDiagnostic(
                resourceID: "invalid.tsv",
                error: .invalidTSVLine(
                    line: 1,
                    reason: "expected pinyin, text, and optional confidence columns"
                )
            )
        ])
    }

    func testLoadFilesReportsUnreadableFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("missing.tsv")

        let catalog = TraditionalInputLexiconFileSource().loadFiles([missingURL])

        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertEqual(catalog.diagnostics.count, 1)
        XCTAssertEqual(catalog.diagnostics.first?.resourceID, "missing.tsv")
        if case .unreadableResource? = catalog.diagnostics.first?.error {
            return
        }
        XCTFail("Expected unreadableResource diagnostic")
    }

    func testLoadDirectorySortsFilesAndSkipsHiddenFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("xi an\t西安\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("02-places.tsv"))
        try Data("ce shi ci\t测试词\t0.91\n".utf8)
            .write(to: directory.appendingPathComponent("01-products.tsv"))
        try Data("hidden\t隐藏\t0.9\n".utf8)
            .write(to: directory.appendingPathComponent(".hidden.tsv"))

        let catalog = TraditionalInputLexiconFileSource().loadDirectory(directory)

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertEqual(catalog.entries.map(\.outputs.first?.text), ["测试词", "西安"])
    }

    func testLoadDirectorySkipsManagedPackMetadataJSON() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("ce shi ci\t测试词\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("user.tsv"))
        try Data(#"{"id":"pack"}"#.utf8)
            .write(to: directory.appendingPathComponent("user.metadata.json"))

        let catalog = TraditionalInputLexiconFileSource().loadDirectory(directory)

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertEqual(catalog.entries.map(\.outputs.first?.text), ["测试词"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeLexiconFileSourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
