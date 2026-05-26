import Foundation
import XCTest
@testable import KnowTypeAI

final class LexicalProfileStoreTests: XCTestCase {
    func testRimeUserDBTextParserAcceptsTabSeparatedFrequencyRows() {
        let content = """
        # Rime user dictionary export
        方案\tfang an\t8
        ce shi\t测试\tc=12 d=0 t=1700000000
        回退方案\tfallback\tc=9 d=0 t=1700000000
        真实词\tzhen1 shi2 ci2\tc=11 d=0 t=1700000000
        fei4 yong4\t费用\tc=13 d=0 t=1700000000
        接口\tjie kou\t3
        123456\tshu zi\t99
        shu zi\t123456\tc=99 d=0 t=1700000000
        API\tapi\t20
        malformed
        方案\tfang an\t10
        """

        let terms = RimeUserDBTextParser(maxTerms: 5).parse(content)

        XCTAssertEqual(terms.map(\.text), ["费用", "测试", "真实词", "方案", "回退方案"])
        XCTAssertEqual(terms.first?.source, "rime-userdb")
        XCTAssertEqual(terms.first?.score, 1)
        XCTAssertLessThan(terms[1].score, 1)
    }

    func testLexicalProfileStoreWritesJSONAndMarkdownMirror() throws {
        let directory = temporaryDirectory()
        let jsonURL = directory.appendingPathComponent("lexical-profile.json")
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                recentCommits: ["请同步这个方案"],
                persistentTerms: [
                    LexicalContextTerm(text: "方案", score: 1, source: "rime-userdb")
                ],
                persistentSourceSummary: ["rime-userdb-snapshot: abc123"]
            )
        )

        let profile = try store.save(
            snapshot: snapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: directory.appendingPathComponent("pinyin_simp.userdb.txt"),
            rimeSnapshotModifiedAt: Date(timeIntervalSince1970: 1),
            generatedAt: Date(timeIntervalSince1970: 2)
        )
        let reloaded = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        XCTAssertEqual(profile.sha256, snapshot.sha256)
        XCTAssertEqual(reloaded.currentSnapshot()?.sha256, snapshot.sha256)
        XCTAssertTrue(markdown.contains("方案"))
        XCTAssertTrue(markdown.contains("rime-userdb"))
    }

    func testLexicalProfileStoreSkipsConditionalSaveWhenGenerationIsStale() throws {
        let directory = temporaryDirectory()
        let jsonURL = directory.appendingPathComponent("lexical-profile.json")
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "不会写入", score: 1, source: "rime-userdb")
                ]
            )
        )

        let profile = try store.saveIfCurrent(
            snapshot: snapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil,
            shouldCommit: { false }
        )

        XCTAssertNil(profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownURL.path))
        XCTAssertNil(store.currentProfile())
    }

    func testLexicalProfileStoreDiscardsPreparedSaveWhenGenerationTurnsStale() throws {
        let directory = temporaryDirectory()
        let jsonURL = directory.appendingPathComponent("lexical-profile.json")
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let oldSnapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "旧画像", score: 1, source: "rime-userdb")
                ]
            )
        )
        let oldProfile = try store.save(
            snapshot: oldSnapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil
        )
        let newSnapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "不应覆盖", score: 1, source: "rime-userdb")
                ]
            )
        )
        var checks = 0

        let profile = try store.saveIfCurrent(
            snapshot: newSnapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil,
            shouldCommit: {
                checks += 1
                return checks == 1
            }
        )

        XCTAssertNil(profile)
        XCTAssertEqual(store.currentProfile()?.sha256, oldProfile.sha256)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode(PersistentLexicalProfile.self, from: Data(contentsOf: jsonURL)).sha256,
            oldProfile.sha256
        )
        XCTAssertTrue(try String(contentsOf: markdownURL, encoding: .utf8).contains("旧画像"))
        XCTAssertFalse(try String(contentsOf: markdownURL, encoding: .utf8).contains("不应覆盖"))
    }

    func testLexicalProfileStoreRollsBackPartialPublishWhenGenerationTurnsStale() throws {
        let directory = temporaryDirectory()
        let jsonURL = directory.appendingPathComponent("lexical-profile.json")
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let oldSnapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "旧画像", score: 1, source: "rime-userdb")
                ]
            )
        )
        let oldProfile = try store.save(
            snapshot: oldSnapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil
        )
        let newSnapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "发布中断", score: 1, source: "rime-userdb")
                ]
            )
        )
        var checks = 0

        let profile = try store.saveIfCurrent(
            snapshot: newSnapshot,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil,
            shouldCommit: {
                checks += 1
                return checks < 5
            }
        )

        XCTAssertNil(profile)
        XCTAssertEqual(store.currentProfile()?.sha256, oldProfile.sha256)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode(PersistentLexicalProfile.self, from: Data(contentsOf: jsonURL)).sha256,
            oldProfile.sha256
        )
        XCTAssertTrue(try String(contentsOf: markdownURL, encoding: .utf8).contains("旧画像"))
        XCTAssertFalse(try String(contentsOf: markdownURL, encoding: .utf8).contains("发布中断"))
    }

    func testLexicalMergeIgnoresRealtimeRimeCandidates() throws {
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                rimeCandidates: ["当前候选"],
                recentCommits: ["这个方向可以继续"],
                selectionHistory: ["刚选过"],
                persistentTerms: [
                    LexicalContextTerm(text: "长期高频", score: 1, source: "rime-userdb")
                ]
            )
        )

        XCTAssertFalse(snapshot.terms.contains { $0.text == "当前候选" })
        XCTAssertTrue(snapshot.terms.contains { $0.text == "长期高频" })
        XCTAssertTrue(snapshot.sourceSummary.contains("rime-userdb: 1"))
        XCTAssertFalse(snapshot.sourceSummary.contains { $0.hasPrefix("rime-candidates:") })
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeLexicalProfileTests-\(UUID().uuidString)", isDirectory: true)
}
