import Foundation
import XCTest
@testable import KnowTypeCore

final class ManagedLexiconPackTests: XCTestCase {
    func testRimeConverterSkipsHeaderAndConvertsRows() throws {
        let source = """
        # Rime dictionary
        ---
        name: fixture
        ...
        你好\tni hao\t20728
        broken
        你是谁\tni shi shei\t134
        为什么\twei shen me\t50907
        没权重\tmei quan zhong
        """

        let result = try RimeDictionaryConverter().convert(Data(source.utf8))
        let converted = String(decoding: result.tsvData, as: UTF8.self)

        XCTAssertEqual(result.entryCount, 4)
        XCTAssertEqual(result.skippedLineCount, 1)
        XCTAssertTrue(converted.contains("ni hao\t你好\t"))
        XCTAssertTrue(converted.contains("ni shi shei\t你是谁\t"))
        XCTAssertTrue(converted.contains("wei shen me\t为什么\t"))
        XCTAssertTrue(converted.contains("mei quan zhong\t没权重\t0.720"))
    }

    func testRimeConvertedRowsFeedTraditionalEngine() throws {
        let source = """
        ---
        name: fixture
        ...
        你是谁\tni shi shei\t134
        为什么\twei shen me\t50907
        现在\txian zai\t246263
        """
        let result = try RimeDictionaryConverter().convert(Data(source.utf8))
        let entries = try TraditionalInputLexiconResourceLoader().loadTSV(result.tsvData)
        let engine = TraditionalInputEngine(additionalLexiconEntries: entries)

        XCTAssertTrue(engine.candidates(for: "nishishei").contains { $0.text == "你是谁" })
        XCTAssertTrue(engine.candidates(for: "weishenme").contains { $0.text == "为什么" })
        XCTAssertTrue(engine.candidates(for: "xianzai").contains { $0.text == "现在" })
    }

    func testRimeConverterRejectsInvalidUTF8() {
        XCTAssertThrowsError(
            try RimeDictionaryConverter().convert(Data([0xFF]))
        ) { error in
            XCTAssertEqual(error as? RimeDictionaryConverterError, .invalidUTF8)
        }
    }

    func testInstallerRejectsChecksumMismatch() async throws {
        let pack = ManagedLexiconPack(
            id: "fixture",
            displayName: "Fixture",
            sourceURL: URL(string: "https://example.com/fixture.dict.yaml")!,
            sourceVersion: "fixture",
            sourceSHA256: "expected",
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://example.com/license")!,
            outputFileName: "fixture.tsv",
            metadataFileName: "fixture.metadata.json",
            format: .rimeDictYAML
        )
        let installer = ManagedLexiconPackInstaller(dataProvider: { _ in
            Data("not matching".utf8)
        })

        do {
            _ = try await installer.install(pack, destinationDirectory: try makeTemporaryDirectory())
            XCTFail("Expected checksum mismatch")
        } catch let error as ManagedLexiconPackInstallerError {
            guard case .checksumMismatch = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testInstallerWritesTSVAndMetadataWithoutOverwritingByDefault() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        ---
        name: fixture
        ...
        你好\tni hao\t20728
        """
        let sourceData = Data(source.utf8)
        let pack = ManagedLexiconPack(
            id: "fixture",
            displayName: "Fixture",
            sourceURL: URL(string: "https://example.com/fixture.dict.yaml")!,
            sourceVersion: "fixture",
            sourceSHA256: ManagedLexiconPackInstaller.sha256Hex(sourceData),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://example.com/license")!,
            outputFileName: "fixture.tsv",
            metadataFileName: "fixture.metadata.json",
            format: .rimeDictYAML
        )
        let installer = ManagedLexiconPackInstaller(
            dataProvider: { _ in sourceData },
            dateProvider: { Date(timeIntervalSince1970: 1_234) }
        )

        let metadata = try await installer.install(pack, destinationDirectory: directory)

        XCTAssertEqual(metadata.entryCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("fixture.tsv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("fixture.metadata.json").path))
        do {
            _ = try await installer.install(pack, destinationDirectory: directory)
            XCTFail("Expected existing output error")
        } catch {
            XCTAssertEqual(
                error as? ManagedLexiconPackInstallerError,
                .outputAlreadyExists(directory.appendingPathComponent("fixture.tsv").path)
            )
        }
    }

    func testInstallerChecksExistingOutputBeforeDownloading() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pack = ManagedLexiconPack(
            id: "fixture",
            displayName: "Fixture",
            sourceURL: URL(string: "https://example.com/fixture.dict.yaml")!,
            sourceVersion: "fixture",
            sourceSHA256: "unused",
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://example.com/license")!,
            outputFileName: "fixture.tsv",
            metadataFileName: "fixture.metadata.json",
            format: .rimeDictYAML
        )
        try Data("old".utf8).write(to: directory.appendingPathComponent("fixture.tsv"))
        let installer = ManagedLexiconPackInstaller(dataProvider: { _ in
            throw URLError(.cannotLoadFromNetwork)
        })

        do {
            _ = try await installer.install(pack, destinationDirectory: directory)
            XCTFail("Expected existing output error")
        } catch {
            XCTAssertEqual(
                error as? ManagedLexiconPackInstallerError,
                .outputAlreadyExists(directory.appendingPathComponent("fixture.tsv").path)
            )
        }
    }

    func testInstallerRechecksExistingOutputAfterDownloadBeforeWriting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        ---
        name: fixture
        ...
        你好\tni hao\t20728
        """
        let sourceData = Data(source.utf8)
        let pack = ManagedLexiconPack(
            id: "fixture",
            displayName: "Fixture",
            sourceURL: URL(string: "https://example.com/fixture.dict.yaml")!,
            sourceVersion: "fixture",
            sourceSHA256: ManagedLexiconPackInstaller.sha256Hex(sourceData),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://example.com/license")!,
            outputFileName: "fixture.tsv",
            metadataFileName: "fixture.metadata.json",
            format: .rimeDictYAML
        )
        let outputURL = directory.appendingPathComponent("fixture.tsv")
        let installer = ManagedLexiconPackInstaller(dataProvider: { _ in
            try Data("concurrent".utf8).write(to: outputURL)
            return sourceData
        })

        do {
            _ = try await installer.install(pack, destinationDirectory: directory)
            XCTFail("Expected existing output error")
        } catch {
            XCTAssertEqual(
                error as? ManagedLexiconPackInstallerError,
                .outputAlreadyExists(outputURL.path)
            )
        }

        XCTAssertEqual(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self), "concurrent")
    }

    func testInstallerForceReplacesExistingOutput() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        ---
        name: fixture
        ...
        你好\tni hao\t20728
        """
        let sourceData = Data(source.utf8)
        let pack = ManagedLexiconPack(
            id: "fixture",
            displayName: "Fixture",
            sourceURL: URL(string: "https://example.com/fixture.dict.yaml")!,
            sourceVersion: "fixture",
            sourceSHA256: ManagedLexiconPackInstaller.sha256Hex(sourceData),
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://example.com/license")!,
            outputFileName: "fixture.tsv",
            metadataFileName: "fixture.metadata.json",
            format: .rimeDictYAML
        )
        try Data("old".utf8).write(to: directory.appendingPathComponent("fixture.tsv"))
        let installer = ManagedLexiconPackInstaller(dataProvider: { _ in sourceData })

        _ = try await installer.install(pack, destinationDirectory: directory, force: true)

        let installed = String(
            decoding: try Data(contentsOf: directory.appendingPathComponent("fixture.tsv")),
            as: UTF8.self
        )
        XCTAssertTrue(installed.contains("ni hao\t你好\t"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeManagedLexiconPackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
