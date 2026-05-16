import Foundation
import XCTest
@testable import KnowTypeSettingsApp

final class LexiconSettingsPresentationTests: XCTestCase {
    func testPresentationShowsMissingDirectoryActionAndStatusRows() throws {
        let directory = URL(fileURLWithPath: "/tmp/KnowType/Lexicons")
        let status = LexiconDirectoryStatus(
            directory: directory,
            exists: false,
            resourceFileCount: 0,
            loadedEntryCount: 0,
            diagnostics: []
        )

        let presentation = LexiconSettingsPresentation(
            totalLoadedEntryCount: 0,
            lastRefreshDate: Date(timeIntervalSince1970: 123),
            directories: [status],
            lastActionMessage: "Created 1 lexicon directory."
        )

        XCTAssertEqual(presentation.loadedEntries, SettingsKeyValuePresentation(label: "Loaded entries", value: "0"))
        XCTAssertEqual(presentation.lastRefreshLabel, "Last refresh")
        XCTAssertEqual(presentation.lastRefreshDate, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(presentation.refreshActionLabel, "Refresh")
        XCTAssertEqual(presentation.createSampleActionLabel, "Create Sample TSV")
        XCTAssertEqual(presentation.createMissingDirectoriesActionLabel, "Create Missing Directories")
        XCTAssertTrue(presentation.showsCreateMissingDirectoriesAction)
        XCTAssertEqual(presentation.lastActionMessage, "Created 1 lexicon directory.")

        let directoryPresentation = try XCTUnwrap(presentation.directories.first)
        XCTAssertEqual(directoryPresentation.sectionTitle, "Directory")
        XCTAssertEqual(directoryPresentation.status, SettingsKeyValuePresentation(label: "Status", value: "Missing"))
        XCTAssertEqual(directoryPresentation.resourceFiles, SettingsKeyValuePresentation(label: "Resource files", value: "0"))
        XCTAssertEqual(directoryPresentation.loadedEntries, SettingsKeyValuePresentation(label: "Loaded entries", value: "0"))
        XCTAssertEqual(directoryPresentation.pathLabel, "Path")
        XCTAssertEqual(directoryPresentation.path, "/tmp/KnowType/Lexicons")
        XCTAssertTrue(directoryPresentation.diagnostics.isEmpty)
    }

    func testPresentationHidesMissingDirectoryActionAndMapsDiagnostics() throws {
        let diagnostic = LexiconDiagnosticStatus(
            resourceID: "broken.tsv",
            message: "Line 1 has too few columns."
        )
        let status = LexiconDirectoryStatus(
            directory: URL(fileURLWithPath: "/tmp/KnowType/Lexicons"),
            exists: true,
            resourceFileCount: 2,
            loadedEntryCount: 1,
            diagnostics: [diagnostic]
        )

        let presentation = LexiconSettingsPresentation(
            totalLoadedEntryCount: 1,
            lastRefreshDate: nil,
            directories: [status],
            lastActionMessage: nil
        )

        XCTAssertEqual(presentation.loadedEntries.value, "1")
        XCTAssertNil(presentation.lastRefreshDate)
        XCTAssertFalse(presentation.showsCreateMissingDirectoriesAction)
        XCTAssertNil(presentation.lastActionMessage)
        XCTAssertEqual(
            presentation.formatRows,
            [
                SettingsKeyValuePresentation(label: "TSV", value: "pinyin<TAB>text<TAB>confidence"),
                SettingsKeyValuePresentation(label: "JSON", value: "TraditionalInputLexiconEntry array")
            ]
        )

        let directoryPresentation = try XCTUnwrap(presentation.directories.first)
        XCTAssertEqual(directoryPresentation.status.value, "Available")
        XCTAssertEqual(directoryPresentation.resourceFiles.value, "2")
        XCTAssertEqual(directoryPresentation.loadedEntries.value, "1")
        let diagnosticPresentation = try XCTUnwrap(directoryPresentation.diagnostics.first)
        XCTAssertEqual(diagnosticPresentation.id, "broken.tsv:Line 1 has too few columns.")
        XCTAssertEqual(diagnosticPresentation.title, "broken.tsv")
        XCTAssertEqual(diagnosticPresentation.message, "Line 1 has too few columns.")
    }
}
