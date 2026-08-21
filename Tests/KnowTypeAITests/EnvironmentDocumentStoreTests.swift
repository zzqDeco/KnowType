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
        let userNotesSections = snapshot.content.components(
            separatedBy: EnvironmentDocumentStore.userNotesTitle
        )
        XCTAssertEqual(userNotesSections.count, 2)
        let canonicalNotes = try XCTUnwrap(
            userNotesSections.last
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            canonicalNotes,
            markerless.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let canonicalLines = snapshot.content.components(separatedBy: "\n")
        XCTAssertEqual(
            canonicalLines.filter { $0 == EnvironmentDocumentStore.generatedStart }.count,
            1
        )
        XCTAssertEqual(
            canonicalLines.filter { $0 == EnvironmentDocumentStore.generatedEnd }.count,
            1
        )
        let generatedStartIndex = try XCTUnwrap(
            canonicalLines.firstIndex(of: EnvironmentDocumentStore.generatedStart)
        )
        let generatedEndIndex = try XCTUnwrap(
            canonicalLines.firstIndex(of: EnvironmentDocumentStore.generatedEnd)
        )
        XCTAssertLessThan(generatedStartIndex, generatedEndIndex)
        XCTAssertNotNil(EnvironmentDocumentStore.generatedSection(from: snapshot.content))
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

    func testMarkerlessUserNotesHeadingKeepsTextBeforeAndAfterExactlyOnce() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let markerless = "before heading\n## User Notes\ninside heading\nafter heading\n"
        try Data(markerless.utf8).write(to: url)
        let store = EnvironmentDocumentStore(fileURL: url)

        let first = try store.loadSnapshot()
        XCTAssertTrue(first.content.contains("before heading"))
        XCTAssertTrue(first.content.contains("inside heading"))
        XCTAssertTrue(first.content.contains("after heading"))
        XCTAssertEqual(first.content.components(separatedBy: EnvironmentDocumentStore.userNotesTitle).count, 2)
        XCTAssertEqual(try store.loadSnapshot(), first)
    }

    func testMarkerfulPairWithoutNotesExtractsOutsideTextWithoutLoss() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let content = """
        # KnowType Environment

        user text before generated

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - stable generated value
        <!-- KNOWTYPE:END GENERATED -->

        user text after generated
        """
        try Data(content.utf8).write(to: url)
        let store = EnvironmentDocumentStore(fileURL: url)

        let first = try store.loadSnapshot()
        XCTAssertTrue(first.content.contains("user text before generated"))
        XCTAssertTrue(first.content.contains("user text after generated"))
        XCTAssertEqual(first.content.components(separatedBy: EnvironmentDocumentStore.userNotesTitle).count, 2)
        XCTAssertEqual(try store.loadSnapshot(), first)
    }

    func testExistingEnvironmentPermissionsAreRestrictedBeforeContentRead() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        try Data(EnvironmentDocumentStore.defaultContent.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        let probe = EnvironmentDocumentStoreTestProbe()
        let store = EnvironmentDocumentStore(fileURL: url, testProbe: probe)

        _ = try store.loadSnapshot()

        let permissions = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(probe.documentReadCount, 1)
    }

    func testEnvironmentPermissionFailureFailsBeforeContentRead() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let content = EnvironmentDocumentStore.defaultContent + "\nprivate fixture"
        try Data(content.utf8).write(to: url)
        let probe = EnvironmentDocumentStoreTestProbe()
        probe.failNextPermissionChanges(1)
        let store = EnvironmentDocumentStore(fileURL: url, testProbe: probe)

        XCTAssertThrowsError(try store.loadSnapshot())

        XCTAssertEqual(probe.documentReadCount, 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)
    }

    func testUserNotesHeadingBeforeInsideOrOverlappingGeneratedPairFailsClosedIdempotently() throws {
        let fixtures = [
            """
            # KnowType Environment

            ## User Notes
            note before pair

            <!-- KNOWTYPE:BEGIN GENERATED -->
            ## Global Style
            - generated
            <!-- KNOWTYPE:END GENERATED -->
            """,
            """
            # KnowType Environment

            <!-- KNOWTYPE:BEGIN GENERATED -->
            ## Global Style
            - generated
            ## User Notes
            note inside pair
            <!-- KNOWTYPE:END GENERATED -->
            """,
            """
            # KnowType Environment

            <!-- KNOWTYPE:BEGIN GENERATED -->
            <!-- KNOWTYPE:BEGIN GENERATED -->
            ## Global Style
            - overlapping generated structure
            <!-- KNOWTYPE:END GENERATED -->
            <!-- KNOWTYPE:END GENERATED -->

            ## User Notes
            note after overlapping pairs
            """
        ]

        for content in fixtures {
            let directory = makeDirectory()
            let url = directory.appendingPathComponent("ENV.md")
            try Data(content.utf8).write(to: url)
            let store = EnvironmentDocumentStore(fileURL: url)

            for _ in 0..<2 {
                XCTAssertThrowsError(try store.loadSnapshot()) { error in
                    XCTAssertEqual(error as? EnvironmentDocumentError, .ambiguousMigration)
                }
                XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)
            }
            let backups = try FileManager.default.contentsOfDirectory(
                at: directory.appendingPathComponent("backups"),
                includingPropertiesForKeys: nil
            )
            XCTAssertEqual(backups.count, 1)
        }
    }

    func testMarkerWordsInsideOrdinaryTextDoNotDefineManagedBoundary() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let literalStart = "keep literal <!-- KNOWTYPE:BEGIN GENERATED --> text"
        let literalEnd = "keep literal <!-- KNOWTYPE:END GENERATED --> text"
        let content = """
        # KnowType Environment

        \(literalStart)

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - stable generated value
        <!-- KNOWTYPE:END GENERATED -->

        \(literalEnd)
        """
        try Data(content.utf8).write(to: url)
        let store = EnvironmentDocumentStore(fileURL: url)

        let first = try store.loadSnapshot()
        XCTAssertEqual(EnvironmentDocumentStore.generatedSection(from: first.content), "## Global Style\n- stable generated value")
        XCTAssertTrue(first.content.contains(literalStart))
        XCTAssertTrue(first.content.contains(literalEnd))
        let canonicalLines = first.content.components(separatedBy: "\n")
        XCTAssertEqual(canonicalLines.filter { $0 == EnvironmentDocumentStore.generatedStart }.count, 1)
        XCTAssertEqual(canonicalLines.filter { $0 == EnvironmentDocumentStore.generatedEnd }.count, 1)
        XCTAssertEqual(try store.loadSnapshot(), first)
    }

    func testAmbiguousUserNotesFailsClosedAndLeavesBackup() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let ambiguous = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - existing
        <!-- KNOWTYPE:END GENERATED -->

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

    func testExistingAuthenticBackupIsVerifiedAndRestrictedBeforeRepair() throws {
        let directory = makeDirectory()
        let url = directory.appendingPathComponent("ENV.md")
        let content = recursivePollutionFixture()
        try Data(content.utf8).write(to: url)
        let backup = try prepareBackupTarget(for: content, in: directory)
        try Data(content.utf8).write(to: backup)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: backup.path
        )

        _ = try EnvironmentDocumentStore(fileURL: url).loadSnapshot()

        let permissions = try FileManager.default.attributesOfItem(
            atPath: backup.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), content)
    }

    func testSuspiciousExistingBackupObjectsBlockRepairWithoutReplacement() throws {
        for kind in ["directory", "symlink", "wrong-content", "oversized"] {
            let directory = makeDirectory()
            let url = directory.appendingPathComponent("ENV.md")
            let content = recursivePollutionFixture()
            try Data(content.utf8).write(to: url)
            let backup = try prepareBackupTarget(for: content, in: directory)
            let symlinkDestination = directory.appendingPathComponent("symlink-destination")

            switch kind {
            case "directory":
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
            case "symlink":
                try Data("external".utf8).write(to: symlinkDestination)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: symlinkDestination.path
                )
                try FileManager.default.createSymbolicLink(
                    at: backup,
                    withDestinationURL: symlinkDestination
                )
            case "oversized":
                try Data(repeating: 0x78, count: Data(content.utf8).count + 1).write(to: backup)
            default:
                try Data("wrong".utf8).write(to: backup)
            }

            XCTAssertThrowsError(
                try EnvironmentDocumentStore(fileURL: url).loadSnapshot()
            )
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)
            switch kind {
            case "directory":
                var isDirectory: ObjCBool = false
                XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path, isDirectory: &isDirectory))
                XCTAssertTrue(isDirectory.boolValue)
            case "symlink":
                XCTAssertEqual(
                    try FileManager.default.destinationOfSymbolicLink(atPath: backup.path),
                    symlinkDestination.path
                )
                XCTAssertEqual(
                    try String(contentsOf: symlinkDestination, encoding: .utf8),
                    "external"
                )
                let permissions = try FileManager.default.attributesOfItem(
                    atPath: symlinkDestination.path
                )[.posixPermissions] as? NSNumber
                XCTAssertEqual(permissions?.intValue, 0o644)
            default:
                if kind == "oversized" {
                    XCTAssertEqual(try Data(contentsOf: backup).count, Data(content.utf8).count + 1)
                } else {
                    XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "wrong")
                }
            }
        }
    }

    func testExistingBackupReadOrPermissionFailureBlocksRepair() throws {
        for failure in ["read", "permission"] {
            let directory = makeDirectory()
            let url = directory.appendingPathComponent("ENV.md")
            let content = recursivePollutionFixture()
            try Data(content.utf8).write(to: url)
            let backup = try prepareBackupTarget(for: content, in: directory)
            try Data(content.utf8).write(to: backup)
            let probe = EnvironmentDocumentStoreTestProbe()
            if failure == "read" {
                probe.failNextBackupReads(2)
            } else {
                probe.failNextBackupPermissionChanges(2)
            }

            XCTAssertThrowsError(
                try EnvironmentDocumentStore(
                    fileURL: url,
                    testProbe: probe
                ).loadSnapshot()
            )
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content)
            XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), content)
        }
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

    private func recursivePollutionFixture() -> String {
        """
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
        preserved note
        """
    }

    private func prepareBackupTarget(for content: String, in directory: URL) throws -> URL {
        let backups = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups.appendingPathComponent("ENV-\(AIDocumentSnapshot.hash(content)).md")
    }
}
