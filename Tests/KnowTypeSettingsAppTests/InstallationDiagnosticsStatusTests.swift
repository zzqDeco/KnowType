import Foundation
import CryptoKit
import KnowTypeCore
import KnowTypeProviders
import XCTest
@testable import KnowTypeSettingsUI

final class InstallationDiagnosticsStatusTests: XCTestCase {
    func testStatusShowsInstallRuntimeAIUserDataAndRollbackRows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-install-status-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let support = root.appendingPathComponent("Support/KnowType", isDirectory: true)
        let bundle = root.appendingPathComponent("KnowType.app", isDirectory: true)
        let prefPane = root.appendingPathComponent("KnowType.prefPane", isDirectory: true)
        try makeBundle(at: bundle, version: "0.2.0", build: "2026052401")
        try FileManager.default.createDirectory(at: prefPane, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("AI", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".knowtype", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: support.appendingPathComponent("AI/lexical-profile.json"))
        try Data("env".utf8).write(to: home.appendingPathComponent(".knowtype/ENV.md"))
        try Data("correction".utf8).write(to: home.appendingPathComponent(".knowtype/CORRECTION.md"))
        try Data("lexical\n- accepted-ai-summary: terms=1 commits=1 history=abc123\n".utf8)
            .write(to: home.appendingPathComponent(".knowtype/LEXICAL_PROFILE.md"))
        let acceptedTextHash = sha256("JSON Schema 可以继续推进")
        let acceptedHistoryHash = sha256(acceptedTextHash)
        try Data(
            """
            {"schemaVersion":1,"acceptedAt":"2026-05-24T00:00:00Z","schemaID":"pinyin_simp","rawInput":"json","acceptedText":"JSON Schema 可以继续推进","provider":"ai-test","contextVersion":"test","textHash":"\(acceptedTextHash)","commitKind":"ai","candidateSource":"ai:ai-test","extractedTerms":[]}

            """.utf8
        ).write(to: support.appendingPathComponent("AI/accepted-ai-learning.jsonl"))
        try writeJSON(
            [
                "schemaVersion": 1,
                "generatedAt": "2026-05-24T00:01:00Z",
                "historyHash": acceptedHistoryHash,
                "acceptedCount": 1,
                "termProfile": [
                    ["text": "JSON", "score": 1.0, "source": "accepted-ai"]
                ],
                "styleProfile": [
                    "register": "neutral",
                    "technicalDensity": 0.5,
                    "codeSwitchingRatio": 0.2,
                    "punctuationStyle": "standard",
                    "connectors": [],
                    "endings": []
                ],
                "recentAcceptedCommits": ["JSON Schema 可以继续推进"],
                "sourceSummary": ["accepted-ai-summary: terms=1 commits=1 history=\(String(acceptedHistoryHash.prefix(8)))"]
            ],
            to: support.appendingPathComponent("AI/accepted-ai-summary.json")
        )
        try Data("Accepted count: 1\n".utf8).write(to: home.appendingPathComponent(".knowtype/ACCEPTED_AI_LEARNING.md"))
        let acceptID = "11111111-1111-1111-1111-111111111111"
        let acceptedFeedbackHash = sha256(
            [
                acceptID,
                acceptedTextHash,
                "12:4",
                "冗长表达",
                "简洁说法",
                "0.5000",
                "strong"
            ].joined(separator: "|")
        )
        try Data(
            """
            {"schemaVersion":1,"observedAt":"2026-05-24T00:02:00Z","acceptID":"\(acceptID)","schemaID":"pinyin_simp","provider":"ai-test","contextVersion":"test","acceptedTextHash":"\(acceptedTextHash)","deletedRanges":[{"location":12,"length":4}],"deletedTexts":["冗长表达"],"deletedVisibleCharacterCount":4,"deletedRatio":0.5,"strength":"strong","replacementText":"简洁说法","reason":"delete_idle"}

            """.utf8
        ).write(to: support.appendingPathComponent("AI/accepted-ai-feedback.jsonl"))
        try writeJSON(
            [
                "schemaVersion": 1,
                "generatedAt": "2026-05-24T00:03:00Z",
                "historyHash": acceptedFeedbackHash,
                "feedbackCount": 1,
                "strongCount": 1,
                "avoidTerms": ["冗长表达"],
                "styleAdjustments": ["Prefer shorter AI continuations when context is ambiguous."],
                "replacementPatterns": [
                    ["deleted": "冗长表达", "replacement": "简洁说法"]
                ],
                "sourceSummary": ["accepted-ai-feedback-summary: records=1 strong=1 history=\(String(acceptedFeedbackHash.prefix(8)))"]
            ],
            to: support.appendingPathComponent("AI/accepted-ai-feedback-summary.json")
        )
        try Data("Feedback count: 1\n".utf8).write(to: home.appendingPathComponent(".knowtype/ACCEPTED_AI_FEEDBACK.md"))

        try writeJSON(
            [
                "schemaVersion": 1,
                "installedAt": "2026-05-24T00:00:00Z",
                "source": "dmg-dev-preview",
                "version": "0.2.0",
                "build": "2026052401",
                "gitCommit": "abc123",
                "gitTag": "v0.2.0",
                "releaseManifestDigest": "digest123",
                "bundlePath": bundle.path,
                "prefPanePath": prefPane.path,
                "previousBackupID": "20260524T000000Z-0000-0.1.0-1"
            ],
            to: support.appendingPathComponent("install-state.json")
        )
        let profile = ProviderProfile(
            id: "spark",
            displayName: "Local Spark",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "gpt-5.3-codex-spark",
            isDefault: true
        )
        let profilesData = try JSONEncoder().encode(ProviderProfilesFile(profiles: [profile]))
        try profilesData.write(to: support.appendingPathComponent("providers.v2.json"))

        let backup = support
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("20260524T000000Z-0000-0.1.0-1", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: backup.appendingPathComponent("KnowType.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeJSON(
            [
                "schemaVersion": 2,
                "backupID": backup.lastPathComponent,
                "createdAt": "2026-05-24T00:00:00Z",
                "sourceVersion": "0.1.0",
                "sourceBuild": "1",
                "bundleIdentifier": "com.knowtype.inputmethod.KnowType",
                "appBundleIdentifier": "com.knowtype.inputmethod.KnowType",
                "appShortVersion": "0.1.0",
                "appBuildVersion": "1",
                "appChecksum": "checksum",
                "appSigningRequirement": "identifier \"com.knowtype.inputmethod.KnowType\"",
                "appSigningIdentity": "identifier=com.knowtype.inputmethod.KnowType",
                "includedPrefPane": true,
                "prefPaneChecksum": "prefpane-checksum",
                "prefPaneBundleIdentifier": "com.knowtype.preferencepane",
                "prefPaneShortVersion": "0.1.0",
                "prefPaneBuildVersion": "1",
                "prefPaneSigningRequirement": "identifier \"com.knowtype.preferencepane\"",
                "prefPaneSigningIdentity": "identifier=com.knowtype.preferencepane",
                "restoreCommand": "./scripts/rollback-inputmethod.sh --to \(backup.lastPathComponent)"
            ],
            to: backup.appendingPathComponent("manifest.json")
        )
        try FileManager.default.createDirectory(
            at: support
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("zzzz-unmanaged", isDirectory: true),
            withIntermediateDirectories: true
        )

        let status = InstallationDiagnosticsStatus(
            applicationSupportURL: support,
            homeDirectoryURL: home,
            inputMethodBundleURL: bundle,
            preferencePaneURL: prefPane,
            runtimePreferences: InputMethodRuntimePreferences(
                cloudContinuationEnabled: true,
                localContinuationEnabledWhenNoProvider: false
            ),
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(value("版本", in: status.installRows), "0.2.0 (2026052401)")
        XCTAssertEqual(value("来源", in: status.installRows), "开发者预览 DMG")
        XCTAssertEqual(value("Commit", in: status.installRows), "abc123")
        XCTAssertEqual(value("Manifest", in: status.installRows), "digest123")
        XCTAssertEqual(value("Rime dylib", in: status.runtimeRows), "存在")
        XCTAssertEqual(value("云端续写", in: status.aiRows), "已启用")
        XCTAssertEqual(value("本地 fallback", in: status.aiRows), "已关闭")
        XCTAssertTrue(value("默认 provider", in: status.aiRows).contains("gpt-5.3-codex-spark"))
        XCTAssertEqual(value("配置存储", in: status.aiRows), "当前")
        XCTAssertNotEqual(value("ENV.md", in: status.userDataRows), "缺失")
        XCTAssertEqual(value("接受记录数", in: status.acceptedLearningRows), "1")
        XCTAssertEqual(value("Summary 状态", in: status.acceptedLearningRows), "当前")
        XCTAssertEqual(value("接受词条", in: status.acceptedLearningRows), "1")
        XCTAssertEqual(value("近期提交", in: status.acceptedLearningRows), "1")
        XCTAssertEqual(value("已进入 LEXICAL_PROFILE.md", in: status.acceptedLearningRows), "是")
        XCTAssertEqual(value("反馈记录数", in: status.acceptedFeedbackRows), "1")
        XCTAssertEqual(value("Feedback Summary", in: status.acceptedFeedbackRows), "当前")
        XCTAssertEqual(value("强反馈", in: status.acceptedFeedbackRows), "1")
        XCTAssertEqual(value("降权词条", in: status.acceptedFeedbackRows), "1")
        XCTAssertEqual(value("ACCEPTED_AI_FEEDBACK.md", in: status.acceptedFeedbackRows), "存在")
        XCTAssertTrue(status.acceptedLearningCommands.contains("./scripts/accepted-learning.sh rebuild"))
        XCTAssertEqual(value("备份数量", in: status.backupRows), "1")
        XCTAssertEqual(status.rollbackCommand, "./scripts/rollback-inputmethod.sh --to 20260524T000000Z-0000-0.1.0-1")
    }

    func testAcceptedLearningCorruptSummaryIsShownAsStale() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-accepted-learning-status-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let support = root.appendingPathComponent("Support/KnowType", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("AI", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".knowtype", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{not-json".utf8).write(to: support.appendingPathComponent("AI/accepted-ai-summary.json"))

        let status = InstallationDiagnosticsStatus(
            applicationSupportURL: support,
            homeDirectoryURL: home,
            inputMethodBundleURL: root.appendingPathComponent("KnowType.app", isDirectory: true),
            preferencePaneURL: root.appendingPathComponent("KnowType.prefPane", isDirectory: true),
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(value("Summary 状态", in: status.acceptedLearningRows), "过期")
    }

    func testProviderDiagnosticSummaryRemovesUserInfoQueryAndFragment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-provider-diagnostic-redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support/KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let profile = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://user:pass@example.com/v1?api_key=TOPSECRET#trace")!,
            model: "gpt-test",
            isDefault: true
        )
        try JSONEncoder().encode(ProviderProfilesFile(revision: 1, profiles: [profile]))
            .write(to: support.appendingPathComponent("providers.v2.json"))

        let status = InstallationDiagnosticsStatus(
            applicationSupportURL: support,
            homeDirectoryURL: root,
            inputMethodBundleURL: root.appendingPathComponent("KnowType.app", isDirectory: true),
            preferencePaneURL: root.appendingPathComponent("KnowType.prefPane", isDirectory: true),
            preferredLanguages: ["zh-Hans-CN"]
        )

        let summary = value("默认 provider", in: status.aiRows)
        XCTAssertTrue(summary.contains("https://example.com/v1"))
        XCTAssertFalse(summary.contains("user"))
        XCTAssertFalse(summary.contains("pass"))
        XCTAssertFalse(summary.contains("api_key"))
        XCTAssertFalse(summary.contains("TOPSECRET"))
        XCTAssertFalse(summary.contains("trace"))
    }

    func testProviderDiagnosticFlagsLegacyWriterWithoutReadingItsProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-provider-diagnostic-legacy-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support/KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let canonical = ProviderProfile(
            id: "canonical",
            displayName: "Canonical",
            kind: .openAIResponses,
            baseURL: URL(string: "https://canonical.example.com/v1")!,
            model: "current-model",
            isDefault: true
        )
        let stale = ProviderProfile(
            id: "stale",
            displayName: "Stale",
            kind: .openAIChat,
            baseURL: URL(string: "https://stale.example.com/v1")!,
            model: "stale-model",
            isDefault: true
        )
        try JSONEncoder().encode(ProviderProfilesFile(revision: 4, profiles: [canonical]))
            .write(to: support.appendingPathComponent("providers.v2.json"))
        try JSONEncoder().encode(ProviderProfilesFile(revision: 1, profiles: [stale]))
            .write(to: support.appendingPathComponent("providers.json"))

        let status = InstallationDiagnosticsStatus(
            applicationSupportURL: support,
            homeDirectoryURL: root,
            inputMethodBundleURL: root.appendingPathComponent("KnowType.app", isDirectory: true),
            preferencePaneURL: root.appendingPathComponent("KnowType.prefPane", isDirectory: true),
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(value("配置存储", in: status.aiRows), "检测到旧版本写入")
        XCTAssertTrue(value("默认 provider", in: status.aiRows).contains("Canonical"))
        XCTAssertFalse(value("默认 provider", in: status.aiRows).contains("Stale"))
    }

    func testProviderDiagnosticReportsExpectedCanonicalAsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-provider-diagnostic-missing-canonical-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support/KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(
            """
            {"canonicalFile":"providers.v2.json","canonicalExpected":true,"profiles":[],"schemaVersion":"migrated-to-providers.v2.json"}
            """.utf8
        ).write(to: support.appendingPathComponent("providers.json"))

        let status = InstallationDiagnosticsStatus(
            applicationSupportURL: support,
            homeDirectoryURL: root,
            inputMethodBundleURL: root.appendingPathComponent("KnowType.app", isDirectory: true),
            preferencePaneURL: root.appendingPathComponent("KnowType.prefPane", isDirectory: true),
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(value("配置存储", in: status.aiRows), "迁移后配置缺失")
    }

    private func makeBundle(at url: URL, version: String, build: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Frameworks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Resources/rime-data", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: contents.appendingPathComponent("Frameworks/librime.1.dylib"))
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.knowtype.inputmethod.KnowType",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func value(_ label: String, in rows: [SettingsKeyValuePresentation]) -> String {
        rows.first { $0.label == label }?.value ?? ""
    }

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
