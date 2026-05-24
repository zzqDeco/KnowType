import Foundation
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
        try Data("lexical".utf8).write(to: home.appendingPathComponent(".knowtype/LEXICAL_PROFILE.md"))

        try writeJSON(
            [
                "schemaVersion": 1,
                "installedAt": "2026-05-24T00:00:00Z",
                "source": "release-zip",
                "version": "0.2.0",
                "build": "2026052401",
                "gitCommit": "abc123",
                "gitTag": "v0.2.0",
                "bundlePath": bundle.path,
                "prefPanePath": prefPane.path,
                "previousBackupID": "20260524T000000Z-0.1.0-1"
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
        try profilesData.write(to: support.appendingPathComponent("providers.json"))

        let backup = support
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("20260524T000000Z-0.1.0-1", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try writeJSON(
            [
                "schemaVersion": 1,
                "backupID": backup.lastPathComponent,
                "createdAt": "2026-05-24T00:00:00Z",
                "sourceVersion": "0.1.0",
                "sourceBuild": "1",
                "bundleIdentifier": "com.knowtype.inputmethod.KnowType",
                "appChecksum": "checksum",
                "includedPrefPane": true,
                "restoreCommand": "./scripts/rollback-inputmethod.sh --to \(backup.lastPathComponent)"
            ],
            to: backup.appendingPathComponent("manifest.json")
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
        XCTAssertEqual(value("来源", in: status.installRows), "release-zip")
        XCTAssertEqual(value("Commit", in: status.installRows), "abc123")
        XCTAssertEqual(value("Rime dylib", in: status.runtimeRows), "存在")
        XCTAssertEqual(value("云端续写", in: status.aiRows), "已启用")
        XCTAssertEqual(value("本地 fallback", in: status.aiRows), "已关闭")
        XCTAssertTrue(value("默认 provider", in: status.aiRows).contains("gpt-5.3-codex-spark"))
        XCTAssertNotEqual(value("ENV.md", in: status.userDataRows), "缺失")
        XCTAssertEqual(value("备份数量", in: status.backupRows), "1")
        XCTAssertEqual(status.rollbackCommand, "./scripts/rollback-inputmethod.sh --to 20260524T000000Z-0.1.0-1")
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
}
