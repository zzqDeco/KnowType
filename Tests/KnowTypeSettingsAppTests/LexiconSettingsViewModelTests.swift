import Foundation
import XCTest
@testable import KnowTypeSettingsApp

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

    func testMissingDirectoryIsSilent() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeMissingLexicon-\(UUID().uuidString)")

        let viewModel = LexiconSettingsViewModel(directoryURLs: [directory])

        XCTAssertEqual(viewModel.totalLoadedEntryCount, 0)
        XCTAssertEqual(viewModel.directories.count, 1)
        XCTAssertEqual(viewModel.directories.first?.exists, false)
        XCTAssertEqual(viewModel.directories.first?.resourceFileCount, 0)
        XCTAssertEqual(viewModel.directories.first?.loadedEntryCount, 0)
        XCTAssertEqual(viewModel.directories.first?.diagnostics, [])
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
