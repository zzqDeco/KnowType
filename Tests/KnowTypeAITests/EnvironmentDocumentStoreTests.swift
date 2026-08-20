import Foundation
import XCTest
@testable import KnowTypeAI

final class EnvironmentDocumentStoreTests: XCTestCase {
    func testDigestCandidateRejectsMarkersTitlesMultipleLinesAndEmptyWithoutWriting() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let store = EnvironmentDocumentStore(fileURL: url)
        let before = try store.loadSnapshot().content

        for candidate in [
            "<!-- KNOWTYPE:BEGIN GENERATED -->",
            "# KnowType Environment",
            "## User Notes",
            "   \n\n"
        ] {
            XCTAssertThrowsError(try store.replaceGeneratedSection(with: candidate))
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), before)
    }

    func testRecursivePollutionBacksUpOnceAndPreservesUserNotesBytes() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let notes = "- keep this exact note\n\n- and this tail\n"
        let polluted = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - old
        <!-- KNOWTYPE:END GENERATED -->

        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - recursive
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        \(notes)
        """
        try Data(polluted.utf8).write(to: url)
        let store = EnvironmentDocumentStore(fileURL: url)
        let snapshot = try store.loadSnapshot()
        XCTAssertEqual(EnvironmentDocumentStore.generatedSection(from: snapshot.content), EnvironmentDocumentStore.generatedSection(from: EnvironmentDocumentStore.defaultContent))
        XCTAssertTrue(snapshot.content.hasSuffix("## User Notes\n\(notes)"))

        let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)
        _ = try store.loadSnapshot()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("backups"), includingPropertiesForKeys: nil).count, 1)
    }

    func testMarkerlessDocumentBecomesUserNotesWithoutProviderContextBackup() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let markerless = "# Personal notes\n- keep markerless content\n"
        try Data(markerless.utf8).write(to: url)
        let snapshot = try EnvironmentDocumentStore(fileURL: url).loadSnapshot()
        XCTAssertTrue(snapshot.content.contains("## User Notes\n\(markerless)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("backups").path))
    }

    func testMarkerlessNotesHeadingsPreserveBothSidesAndRemainIdempotent() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let markerless = "# Personal notes\n- before heading\n## User Notes\n- between headings\n## User Notes\n- after heading\n"
        try Data(markerless.utf8).write(to: url)
        let store = EnvironmentDocumentStore(fileURL: url)

        let first = try store.loadSnapshot()
        XCTAssertTrue(first.content.contains("- before heading"))
        XCTAssertTrue(first.content.contains("- between headings"))
        XCTAssertTrue(first.content.contains("- after heading"))
        XCTAssertEqual(first.content.components(separatedBy: EnvironmentDocumentStore.userNotesTitle).count, 2)

        let second = try store.loadSnapshot()
        XCTAssertEqual(second, first)
    }

    func testAmbiguousUserNotesFailsClosedAndLeavesBackup() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let ambiguous = """
        # KnowType Environment
        ## User Notes
        one
        ## User Notes
        two
        """
        try Data(ambiguous.utf8).write(to: url)
        XCTAssertThrowsError(try EnvironmentDocumentStore(fileURL: url).loadSnapshot()) { error in
            XCTAssertEqual(error as? EnvironmentDocumentError, .ambiguousMigration)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("backups").path))
    }

    func testDigestClaimContainsOnlyHashesAndCounts() throws {
        let directory = makeDirectory()
        let store = EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md"))
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: String(repeating: "a", count: 64),
            claimedPrefixByteCount: 100,
            claimedEventCount: 2,
            generatedSHA256: String(repeating: "b", count: 64),
            providerGeneration: 3
        )
        try store.saveDigestClaim(claim)
        let data = try Data(contentsOf: directory.appendingPathComponent("ENV.digest-claim.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("notes"))
        XCTAssertEqual(try store.loadDigestClaim(), claim)
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
