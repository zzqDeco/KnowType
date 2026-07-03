import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeSettingsUI

@MainActor
final class LexiconSettingsViewModelTests: XCTestCase {
    func testDefaultDirectoryUsesKnowTypeApplicationSupport() {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")

        XCTAssertEqual(
            LexiconSettingsViewModel.defaultLexiconDirectories(environment: [:], homeDirectory: home).map(\.path),
            ["/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"]
        )
    }

    func testDefaultDirectoriesUseEnvironmentBeforeApplicationSupport() {
        let home = URL(fileURLWithPath: "/tmp/knowtype-home")

        XCTAssertEqual(
            LexiconSettingsViewModel.defaultLexiconDirectories(
                environment: [
                    LexiconSettingsViewModel.environmentDirectoryKey: "/tmp/one",
                    LexiconSettingsViewModel.environmentDirectoriesKey: "/tmp/two:/tmp/one:/tmp/three"
                ],
                homeDirectory: home
            ).map(\.path),
            [
                "/tmp/one",
                "/tmp/two",
                "/tmp/three",
                "/tmp/knowtype-home/Library/Application Support/KnowType/Lexicons"
            ]
        )
    }

    func testRefreshLoadsEntriesAndReportsDiagnostics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ce shi ci\t测试词\t0.99\n".utf8)
            .write(to: directory.appendingPathComponent("valid.tsv"))
        try Data("broken row\n".utf8)
            .write(to: directory.appendingPathComponent("invalid.tsv"))

        let viewModel = LexiconSettingsViewModel(
            directoryURLs: [directory],
            dateProvider: { Date(timeIntervalSince1970: 1_234) }
        )

        XCTAssertEqual(viewModel.totalLoadedEntryCount, 1)
        XCTAssertEqual(viewModel.lastRefreshDate, Date(timeIntervalSince1970: 1_234))
        XCTAssertEqual(viewModel.directories.count, 1)
        XCTAssertEqual(viewModel.directories.first?.exists, true)
        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 2)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 1)
        XCTAssertEqual(viewModel.directories.first?.diagnostics.count, 1)
        XCTAssertEqual(viewModel.directories.first?.diagnostics.first?.resourceID, "invalid.tsv")
    }

    func testRefreshReportsInstalledManagedPackMetadataWithoutCountingItAsResource() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ce shi ci\t测试词\t0.99\n".utf8)
            .write(to: directory.appendingPathComponent("valid.tsv"))
        let metadata = """
        {
          "displayName" : "Fixture Pack",
          "entryCount" : 1,
          "id" : "fixture",
          "installedAt" : "1970-01-01T00:20:34Z",
          "licenseName" : "Apache-2.0",
          "licenseURL" : "https://example.com/license",
          "outputFileName" : "fixture.tsv",
          "sourceSHA256" : "abc",
          "sourceURL" : "https://example.com/source",
          "sourceVersion" : "fixture"
        }
        """
        try Data(metadata.utf8).write(to: directory.appendingPathComponent("rime-pinyin-simp.metadata.json"))

        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 1)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 1)
        XCTAssertEqual(viewModel.directories.first?.installedPacks.first?.displayName, "Fixture Pack")
        XCTAssertEqual(viewModel.directories.first?.installedPacks.first?.entryCount, 1)
    }

    func testMissingDirectoryIsSilent() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeMissingLexicon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertEqual(viewModel.totalLoadedEntryCount, 0)
        XCTAssertEqual(viewModel.directories.count, 1)
        XCTAssertEqual(viewModel.directories.first?.exists, false)
        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 0)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 0)
        XCTAssertEqual(viewModel.directories.first?.diagnostics, [])
    }

    func testCreateMissingDirectoriesCreatesAndRefreshesStatus() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeCreateLexicon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertEqual(viewModel.directories.first?.exists, false)

        XCTAssertTrue(viewModel.createMissingDirectories())

        XCTAssertEqual(viewModel.directories.first?.exists, true)
        XCTAssertEqual(viewModel.lastActionMessage, "已创建 1 个词库目录。")
    }

    func testCreateMissingDirectoriesReportsNoopWhenAllExist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertTrue(viewModel.createMissingDirectories())

        XCTAssertEqual(viewModel.directories.first?.exists, true)
        XCTAssertEqual(viewModel.lastActionMessage, "所有词库目录都已存在。")
    }

    func testCreateSampleLexiconResourceCreatesDirectoryAndRefreshesStatus() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeSampleLexicon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertTrue(viewModel.createSampleLexiconResource())

        let file = directory.appendingPathComponent(LexiconSettingsViewModel.sampleResourceFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(viewModel.directories.first?.exists, true)
        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 1)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 2)
        XCTAssertEqual(viewModel.lastActionMessage, "已创建 knowtype-sample.tsv。")
    }

    func testCreateSampleLexiconResourceDoesNotOverwriteExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(LexiconSettingsViewModel.sampleResourceFileName)
        try Data("zi zao ci\t已有词\t0.5\n".utf8).write(to: file)
        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertTrue(viewModel.createSampleLexiconResource())

        XCTAssertEqual(
            String(decoding: try Data(contentsOf: file), as: UTF8.self),
            "zi zao ci\t已有词\t0.5\n"
        )
        XCTAssertEqual(viewModel.lastActionMessage, "knowtype-sample.tsv 已存在。")
    }

    func testInstallRecommendedLexiconPackCreatesDirectoryAndRefreshesStatus() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeInstallRecommendedLexicon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = LexiconSettingsViewModel(
            directoryURLs: [directory],
            recommendedPackInstaller: { pack, directory, _ in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("ni hao\t你好\t0.99\n".utf8)
                    .write(to: directory.appendingPathComponent(pack.outputFileName))
                let metadata = InstalledLexiconPackMetadata(
                    id: pack.id,
                    displayName: pack.displayName,
                    sourceURL: pack.sourceURL,
                    sourceVersion: pack.sourceVersion,
                    sourceSHA256: pack.sourceSHA256,
                    outputFileName: pack.outputFileName,
                    entryCount: 1,
                    licenseName: pack.licenseName,
                    licenseURL: pack.licenseURL,
                    installedAt: Date(timeIntervalSince1970: 1_234)
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(metadata)
                    .write(to: directory.appendingPathComponent(pack.metadataFileName))
                return metadata
            }
        )

        let installed = await viewModel.installRecommendedLexiconPack()

        XCTAssertTrue(installed)
        XCTAssertEqual(viewModel.lastActionMessage, "已安装 Rime Pinyin Simplified，共 1 条词条。")
        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 1)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 1)
        XCTAssertEqual(viewModel.directories.first?.installedPacks.first?.id, "rime-pinyin-simp")
        XCTAssertFalse(viewModel.isInstallingRecommendedPack)
    }

    func testInstallRecommendedLexiconPackKeepsExistingStatusOnFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("ni hao\t你好\t0.99\n".utf8)
            .write(to: directory.appendingPathComponent("valid.tsv"))
        let viewModel = LexiconSettingsViewModel(
            directoryURLs: [directory],
            recommendedPackInstaller: { _, _, _ in
                throw ManagedLexiconPackInstallerError.outputAlreadyExists("fixture.tsv")
            }
        )

        let installed = await viewModel.installRecommendedLexiconPack()

        XCTAssertFalse(installed)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 1)
        XCTAssertEqual(viewModel.lastActionMessage, "Lexicon pack output already exists: fixture.tsv")
        XCTAssertFalse(viewModel.isInstallingRecommendedPack)
    }

    func testDuplicateDirectoriesAreShownOnce() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory, directory])

        XCTAssertEqual(viewModel.directories.map(\.directory.path), [directory.path])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeLexiconSettingsViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
