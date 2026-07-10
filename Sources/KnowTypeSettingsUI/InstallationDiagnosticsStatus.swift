import Foundation
import CryptoKit
import KnowTypeCore
import KnowTypeProviders

struct InstallationDiagnosticsStatus: Equatable, Sendable {
    var installRows: [SettingsKeyValuePresentation]
    var runtimeRows: [SettingsKeyValuePresentation]
    var aiRows: [SettingsKeyValuePresentation]
    var userDataRows: [SettingsKeyValuePresentation]
    var acceptedLearningRows: [SettingsKeyValuePresentation]
    var acceptedFeedbackRows: [SettingsKeyValuePresentation]
    var acceptedLearningCommands: [String]
    var backupRows: [SettingsKeyValuePresentation]
    var rollbackCommand: String?

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        homeDirectoryURL: URL? = nil,
        inputMethodBundleURL: URL? = nil,
        preferencePaneURL: URL? = nil,
        runtimePreferences: InputMethodRuntimePreferences = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore().loadPreferences(),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        let homeURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        let supportURL = applicationSupportURL ?? homeURL
            .appendingPathComponent("Library/Application Support/KnowType", isDirectory: true)
        let bundleURL = inputMethodBundleURL ?? homeURL
            .appendingPathComponent("Library/Input Methods/KnowType.app", isDirectory: true)
        let prefPaneURL = preferencePaneURL ?? homeURL
            .appendingPathComponent("Library/PreferencePanes/KnowType.prefPane", isDirectory: true)
        let installState = Self.loadInstallState(from: supportURL.appendingPathComponent("install-state.json"))
        let bundleInfo = Self.bundleInfo(at: bundleURL)
        let providerStorage = Self.providerStorageSummary(
            supportURL: supportURL,
            fileManager: fileManager,
            preferredLanguages: preferredLanguages
        )
        let backupSummary = Self.backupSummary(
            in: supportURL.appendingPathComponent("Backups", isDirectory: true),
            fileManager: fileManager
        )

        installRows = [
            Self.row("settings.diagnostics.install.version", bundleInfo.versionBuild ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.source", Self.installSourceDisplay(installState?.source, preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.commit", installState?.gitCommit ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.tag", installState?.gitTag ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.manifest", installState?.releaseManifestDigest ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.installedAt", installState?.installedAt ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.path", bundleURL.path, preferredLanguages)
        ]

        runtimeRows = [
            Self.row("settings.diagnostics.runtime.bundle", Self.exists(fileManager.fileExists(atPath: bundleURL.path), preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.runtime.prefpane", Self.exists(fileManager.fileExists(atPath: prefPaneURL.path), preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.runtime.rimeDylib", Self.exists(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Frameworks/librime.1.dylib").path), preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.runtime.rimeData", Self.exists(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Resources/rime-data").path), preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.runtime.rimeUserData", supportURL.appendingPathComponent("Rime", isDirectory: true).path, preferredLanguages)
        ]

        aiRows = [
            Self.row("settings.diagnostics.ai.cloud", runtimePreferences.cloudContinuationEnabled ? Self.enabled(preferredLanguages) : Self.disabled(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.ai.localFallback", runtimePreferences.localContinuationEnabledWhenNoProvider ? Self.enabled(preferredLanguages) : Self.disabled(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.ai.provider", providerStorage.defaultProvider ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.ai.storage", providerStorage.state, preferredLanguages)
        ]

        userDataRows = [
            Self.fileRow("settings.diagnostics.userData.lexicalJSON", supportURL.appendingPathComponent("AI/lexical-profile.json"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.env", homeURL.appendingPathComponent(".knowtype/ENV.md"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.correction", homeURL.appendingPathComponent(".knowtype/CORRECTION.md"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.lexicalMarkdown", homeURL.appendingPathComponent(".knowtype/LEXICAL_PROFILE.md"), fileManager, preferredLanguages)
        ]

        let acceptedLearning = Self.acceptedLearningSummary(
            supportURL: supportURL,
            homeURL: homeURL,
            fileManager: fileManager,
            preferredLanguages: preferredLanguages
        )
        acceptedLearningRows = acceptedLearning
        acceptedFeedbackRows = Self.acceptedFeedbackSummary(
            supportURL: supportURL,
            homeURL: homeURL,
            fileManager: fileManager,
            preferredLanguages: preferredLanguages
        )
        acceptedLearningCommands = [
            "./scripts/accepted-learning.sh status",
            "./scripts/accepted-learning.sh rebuild",
            "./scripts/accepted-learning.sh clear --yes"
        ]

        backupRows = [
            Self.row("settings.diagnostics.backup.count", "\(backupSummary.count)", preferredLanguages),
            Self.row("settings.diagnostics.backup.latest", backupSummary.latestID ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.backup.version", backupSummary.latestVersionBuild ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.backup.path", supportURL.appendingPathComponent("Backups", isDirectory: true).path, preferredLanguages)
        ]
        rollbackCommand = backupSummary.latestID.map { "./scripts/rollback-inputmethod.sh --to \($0)" }
    }

    private static func row(_ key: String, _ value: String, _ preferredLanguages: [String]) -> SettingsKeyValuePresentation {
        SettingsKeyValuePresentation(
            label: SettingsLocalization.string(key, preferredLanguages: preferredLanguages),
            value: value
        )
    }

    private static func fileRow(
        _ key: String,
        _ url: URL,
        _ fileManager: FileManager,
        _ preferredLanguages: [String]
    ) -> SettingsKeyValuePresentation {
        guard fileManager.fileExists(atPath: url.path) else {
            return Self.row(key, Self.missing(preferredLanguages), preferredLanguages)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date)
            .map(Self.dateString(_:)) ?? Self.exists(true, preferredLanguages)
        return Self.row(key, modifiedAt, preferredLanguages)
    }

    private static func acceptedLearningSummary(
        supportURL: URL,
        homeURL: URL,
        fileManager: FileManager,
        preferredLanguages: [String]
    ) -> [SettingsKeyValuePresentation] {
        let historyURL = supportURL.appendingPathComponent("AI/accepted-ai-learning.jsonl")
        let summaryURL = supportURL.appendingPathComponent("AI/accepted-ai-summary.json")
        let lexicalMarkdownURL = homeURL.appendingPathComponent(".knowtype/LEXICAL_PROFILE.md")

        let history = acceptedLearningHistory(at: historyURL)
        let summary = acceptedLearningSummaryFile(at: summaryURL)
        let summaryExists = fileManager.fileExists(atPath: summaryURL.path)
        let summaryState: String
        if history.recordCount == 0, summary == nil, !summaryExists {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.current",
                preferredLanguages: preferredLanguages
            )
        } else if let summary,
                  summary.acceptedCount == history.recordCount,
                  summary.historyHash == history.historyHash {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.current",
                preferredLanguages: preferredLanguages
            )
        } else if summary == nil, !summaryExists {
            summaryState = Self.missing(preferredLanguages)
        } else {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.stale",
                preferredLanguages: preferredLanguages
            )
        }

        let lexicalInjected = (try? String(contentsOf: lexicalMarkdownURL, encoding: .utf8))
            .map { $0.contains("accepted-ai-summary:") } ?? false

        return [
            Self.row("settings.diagnostics.acceptedLearning.records", "\(history.recordCount)", preferredLanguages),
            Self.row("settings.diagnostics.acceptedLearning.summary", summaryState, preferredLanguages),
            Self.row("settings.diagnostics.acceptedLearning.generatedAt", summary?.generatedAt ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.acceptedLearning.terms", "\(summary?.termCount ?? 0)", preferredLanguages),
            Self.row("settings.diagnostics.acceptedLearning.recentCommits", "\(summary?.recentCommitCount ?? 0)", preferredLanguages),
            Self.row(
                "settings.diagnostics.acceptedLearning.lexicalInjected",
                SettingsLocalization.string(
                    lexicalInjected ? "settings.diagnostics.status.yes" : "settings.diagnostics.status.no",
                    preferredLanguages: preferredLanguages
                ),
                preferredLanguages
            )
        ]
    }

    private static func acceptedFeedbackSummary(
        supportURL: URL,
        homeURL: URL,
        fileManager: FileManager,
        preferredLanguages: [String]
    ) -> [SettingsKeyValuePresentation] {
        let historyURL = supportURL.appendingPathComponent("AI/accepted-ai-feedback.jsonl")
        let summaryURL = supportURL.appendingPathComponent("AI/accepted-ai-feedback-summary.json")
        let mirrorURL = homeURL.appendingPathComponent(".knowtype/ACCEPTED_AI_FEEDBACK.md")
        let history = acceptedFeedbackHistory(at: historyURL)
        let summary = acceptedFeedbackSummaryFile(at: summaryURL)
        let summaryExists = fileManager.fileExists(atPath: summaryURL.path)
        let summaryState: String
        if history.recordCount == 0, summary == nil, !summaryExists {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.current",
                preferredLanguages: preferredLanguages
            )
        } else if let summary,
                  summary.feedbackCount == history.recordCount,
                  summary.historyHash == history.historyHash {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.current",
                preferredLanguages: preferredLanguages
            )
        } else if summary == nil, !summaryExists {
            summaryState = Self.missing(preferredLanguages)
        } else {
            summaryState = SettingsLocalization.string(
                "settings.diagnostics.acceptedLearning.summary.stale",
                preferredLanguages: preferredLanguages
            )
        }

        return [
            Self.row("settings.diagnostics.acceptedFeedback.records", "\(history.recordCount)", preferredLanguages),
            Self.row("settings.diagnostics.acceptedFeedback.summary", summaryState, preferredLanguages),
            Self.row("settings.diagnostics.acceptedFeedback.generatedAt", summary?.generatedAt ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.acceptedFeedback.strong", "\(summary?.strongCount ?? 0)", preferredLanguages),
            Self.row("settings.diagnostics.acceptedFeedback.avoidTerms", "\(summary?.avoidTermCount ?? 0)", preferredLanguages),
            Self.row(
                "settings.diagnostics.acceptedFeedback.mirror",
                Self.exists(fileManager.fileExists(atPath: mirrorURL.path), preferredLanguages),
                preferredLanguages
            )
        ]
    }

    private static func acceptedLearningHistory(at url: URL) -> (recordCount: Int, historyHash: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (0, nil)
        }
        var textHashes: [String] = []
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let textHash = object["textHash"] as? String else {
                continue
            }
            textHashes.append(textHash)
        }
        guard !textHashes.isEmpty else {
            return (0, nil)
        }
        let hash = SHA256.hash(data: Data(textHashes.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return (textHashes.count, hash)
    }

    private static func acceptedLearningSummaryFile(at url: URL) -> AcceptedLearningSummaryFile? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AcceptedLearningSummaryFile(
            generatedAt: object["generatedAt"] as? String,
            historyHash: object["historyHash"] as? String,
            acceptedCount: object["acceptedCount"] as? Int ?? 0,
            termCount: (object["termProfile"] as? [Any])?.count ?? 0,
            recentCommitCount: (object["recentAcceptedCommits"] as? [Any])?.count ?? 0
        )
    }

    private static func acceptedFeedbackHistory(at url: URL) -> (recordCount: Int, historyHash: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (0, nil)
        }
        var fragments: [String] = []
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let ranges = (object["deletedRanges"] as? [[String: Any]] ?? [])
                .map { "\($0["location"] ?? ""):\($0["length"] ?? "")" }
                .joined(separator: ",")
            let ratio = String(format: "%.4f", object["deletedRatio"] as? Double ?? 0)
            let deletedTexts = (object["deletedTexts"] as? [String] ?? []).joined(separator: "\u{1F}")
            fragments.append([
                object["acceptID"] as? String ?? "",
                object["acceptedTextHash"] as? String ?? "",
                ranges,
                deletedTexts,
                object["replacementText"] as? String ?? "",
                ratio,
                object["strength"] as? String ?? ""
            ].joined(separator: "|"))
        }
        guard !fragments.isEmpty else {
            return (0, nil)
        }
        let hash = SHA256.hash(data: Data(fragments.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return (fragments.count, hash)
    }

    private static func acceptedFeedbackSummaryFile(at url: URL) -> AcceptedFeedbackSummaryFile? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return AcceptedFeedbackSummaryFile(
            generatedAt: object["generatedAt"] as? String,
            historyHash: object["historyHash"] as? String,
            feedbackCount: object["feedbackCount"] as? Int ?? 0,
            strongCount: object["strongCount"] as? Int ?? 0,
            avoidTermCount: (object["avoidTerms"] as? [Any])?.count ?? 0
        )
    }

    private static func exists(_ value: Bool, _ preferredLanguages: [String]) -> String {
        SettingsLocalization.string(
            value ? "settings.diagnostics.status.exists" : "settings.diagnostics.status.missing",
            preferredLanguages: preferredLanguages
        )
    }

    private static func enabled(_ preferredLanguages: [String]) -> String {
        SettingsLocalization.string("settings.diagnostics.status.enabled", preferredLanguages: preferredLanguages)
    }

    private static func disabled(_ preferredLanguages: [String]) -> String {
        SettingsLocalization.string("settings.diagnostics.status.disabled", preferredLanguages: preferredLanguages)
    }

    private static func missing(_ preferredLanguages: [String]) -> String {
        SettingsLocalization.string("settings.diagnostics.status.missing", preferredLanguages: preferredLanguages)
    }

    private static func installSourceDisplay(_ source: String?, _ preferredLanguages: [String]) -> String {
        guard let source, !source.isEmpty else {
            return Self.missing(preferredLanguages)
        }
        let key: String
        switch source {
        case "dmg-dev-preview":
            key = "settings.diagnostics.install.source.dmgDevPreview"
        case "release-zip":
            key = "settings.diagnostics.install.source.releaseZip"
        case "local-build":
            key = "settings.diagnostics.install.source.localBuild"
        case "bundle":
            key = "settings.diagnostics.install.source.bundle"
        default:
            return source
        }
        return SettingsLocalization.string(key, preferredLanguages: preferredLanguages)
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func loadInstallState(from url: URL) -> InstallState? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(InstallState.self, from: data)
    }

    private static func bundleInfo(at url: URL) -> BundleInfo {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return BundleInfo(version: nil, build: nil)
        }
        return BundleInfo(
            version: plist["CFBundleShortVersionString"] as? String,
            build: plist["CFBundleVersion"] as? String
        )
    }

    private static func defaultProviderSummary(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let profilesFile = try? JSONDecoder().decode(ProviderProfilesFile.self, from: data),
              let profile = profilesFile.profiles.first(where: \.isDefault) else {
            return nil
        }
        return "\(profile.displayName) · \(profile.kind.rawValue) · \(profile.model) · \(ProviderEndpointURLPolicy.privacySafeSummary(profile.baseURL))"
    }

    private static func providerStorageSummary(
        supportURL: URL,
        fileManager: FileManager,
        preferredLanguages: [String]
    ) -> ProviderStorageSummary {
        let canonicalURL = supportURL.appendingPathComponent(FileProviderProfileStore.canonicalFilename)
        let legacyURL = supportURL.appendingPathComponent(FileProviderProfileStore.legacyFilename)
        let snapshotURL = supportURL.appendingPathComponent(FileProviderProfileStore.legacySnapshotFilename)
        let legacyData = try? Data(contentsOf: legacyURL)
        let legacyObject = legacyData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let legacyIsTombstone = legacyObject?["schemaVersion"] as? String
            == FileProviderProfileStore.legacyTombstoneSchemaVersion
            && legacyObject?["canonicalFile"] as? String
            == FileProviderProfileStore.canonicalFilename
        let legacyExpectsCanonical = (legacyObject?["canonicalExpected"] as? Bool)
            ?? fileManager.fileExists(atPath: snapshotURL.path)
        let legacyExists = fileManager.fileExists(atPath: legacyURL.path)
        let legacyIsConfiguration = legacyExists && !legacyIsTombstone

        let providerURL: URL
        let stateKey: String
        if fileManager.fileExists(atPath: canonicalURL.path) {
            providerURL = canonicalURL
            stateKey = legacyIsConfiguration
                ? "settings.diagnostics.ai.storage.legacyDiverged"
                : "settings.diagnostics.ai.storage.canonical"
        } else if legacyIsConfiguration {
            providerURL = legacyURL
            stateKey = "settings.diagnostics.ai.storage.legacyUnmigrated"
        } else if legacyIsTombstone, legacyExpectsCanonical {
            providerURL = canonicalURL
            stateKey = "settings.diagnostics.ai.storage.canonicalMissing"
        } else if legacyIsTombstone {
            providerURL = canonicalURL
            stateKey = "settings.diagnostics.ai.storage.initialized"
        } else {
            providerURL = canonicalURL
            stateKey = "settings.diagnostics.ai.storage.missing"
        }

        return ProviderStorageSummary(
            defaultProvider: Self.defaultProviderSummary(from: providerURL),
            state: SettingsLocalization.string(stateKey, preferredLanguages: preferredLanguages)
        )
    }

    private static func backupSummary(in rootURL: URL, fileManager: FileManager) -> BackupSummary {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            return BackupSummary(count: 0, latestID: nil, latestVersionBuild: nil)
        }
        let backupDirectories = contents.filter {
            Self.isManagedBackupDirectory($0, fileManager: fileManager)
        }.sorted {
            $0.lastPathComponent > $1.lastPathComponent
        }
        guard let latest = backupDirectories.first else {
            return BackupSummary(count: 0, latestID: nil, latestVersionBuild: nil)
        }
        let manifestURL = latest.appendingPathComponent("manifest.json")
        let manifest = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode(BackupManifest.self, from: $0) }
        let versionBuild = manifest.map { "\($0.sourceVersion) (\($0.sourceBuild))" }
        return BackupSummary(
            count: backupDirectories.count,
            latestID: latest.lastPathComponent,
            latestVersionBuild: versionBuild
        )
    }

    private static func isManagedBackupDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard url.lastPathComponent.range(
            of: #"^\d{8}T\d{6}Z-\d{4}-"#,
            options: .regularExpression
        ) != nil else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.appendingPathComponent("KnowType.app", isDirectory: true).path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else {
            return false
        }
        return manifest.backupID == url.lastPathComponent
    }
}

private struct ProviderStorageSummary {
    var defaultProvider: String?
    var state: String
}

private struct InstallState: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var installedAt: String
    var source: String
    var version: String
    var build: String
    var gitCommit: String?
    var gitTag: String?
    var bundlePath: String
    var prefPanePath: String?
    var previousBackupID: String?
    var releaseManifestDigest: String?
}

private struct BackupManifest: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var backupID: String
    var createdAt: String
    var sourceVersion: String
    var sourceBuild: String
    var bundleIdentifier: String
    var appChecksum: String
    var includedPrefPane: Bool
    var restoreCommand: String
}

private struct BundleInfo: Equatable, Sendable {
    var version: String?
    var build: String?

    var versionBuild: String? {
        guard let version, let build else {
            return version ?? build
        }
        return "\(version) (\(build))"
    }
}

private struct BackupSummary: Equatable, Sendable {
    var count: Int
    var latestID: String?
    var latestVersionBuild: String?
}

private struct AcceptedLearningSummaryFile: Equatable, Sendable {
    var generatedAt: String?
    var historyHash: String?
    var acceptedCount: Int
    var termCount: Int
    var recentCommitCount: Int
}

private struct AcceptedFeedbackSummaryFile: Equatable, Sendable {
    var generatedAt: String?
    var historyHash: String?
    var feedbackCount: Int
    var strongCount: Int
    var avoidTermCount: Int
}
