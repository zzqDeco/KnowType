import Foundation
import KnowTypeCore
import KnowTypeProviders

struct InstallationDiagnosticsStatus: Equatable, Sendable {
    var installRows: [SettingsKeyValuePresentation]
    var runtimeRows: [SettingsKeyValuePresentation]
    var aiRows: [SettingsKeyValuePresentation]
    var userDataRows: [SettingsKeyValuePresentation]
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
        let providerSummary = Self.defaultProviderSummary(from: supportURL.appendingPathComponent("providers.json"))
        let backupSummary = Self.backupSummary(
            in: supportURL.appendingPathComponent("Backups", isDirectory: true),
            fileManager: fileManager
        )

        installRows = [
            Self.row("settings.diagnostics.install.version", bundleInfo.versionBuild ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.source", installState?.source ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.commit", installState?.gitCommit ?? Self.missing(preferredLanguages), preferredLanguages),
            Self.row("settings.diagnostics.install.tag", installState?.gitTag ?? Self.missing(preferredLanguages), preferredLanguages),
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
            Self.row("settings.diagnostics.ai.provider", providerSummary ?? Self.missing(preferredLanguages), preferredLanguages)
        ]

        userDataRows = [
            Self.fileRow("settings.diagnostics.userData.lexicalJSON", supportURL.appendingPathComponent("AI/lexical-profile.json"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.env", homeURL.appendingPathComponent(".knowtype/ENV.md"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.correction", homeURL.appendingPathComponent(".knowtype/CORRECTION.md"), fileManager, preferredLanguages),
            Self.fileRow("settings.diagnostics.userData.lexicalMarkdown", homeURL.appendingPathComponent(".knowtype/LEXICAL_PROFILE.md"), fileManager, preferredLanguages)
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
        return "\(profile.displayName) · \(profile.kind.rawValue) · \(profile.model) · \(profile.baseURL.absoluteString)"
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
