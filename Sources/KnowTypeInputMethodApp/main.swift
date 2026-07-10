#if canImport(InputMethodKit)
import AppKit
import Carbon
import InputMethodKit
import KnowTypeCore
import KnowTypeInputMethod
import KnowTypeInputSourceSupport
import KnowTypeProviders
import OSLog

private let inputMethodLogger = Logger(
    subsystem: "com.knowtype.inputmethod.KnowType",
    category: "input-method-app"
)

private enum TextInputSourceActivation {
    private static let parentInputSourceID = KnowTypeInputSourceIDs.parent
    private static let activeInputSourceID = KnowTypeInputSourceIDs.activeMode
    private static let legacyModeInputSourceIDs = KnowTypeInputSourceIDs.legacyModes
    private static let fallbackInputSourceID = KnowTypeInputSourceIDs.fallback
    private typealias LSSupport = KnowTypeLaunchServicesSupport
    private typealias TISSupport = KnowTypeTISSupport

    private static let explicitCommandFlags: Set<String> = [
        "--knowtype-rime-smoke",
        "--knowtype-switch-away",
        "--knowtype-purge-legacy",
        "--knowtype-disable-input-source",
        "--knowtype-migrate-provider-profiles",
        "--knowtype-downgrade-provider-profiles",
        "--knowtype-rollback-provider-profile-migration",
        "--knowtype-install-activate",
        "--knowtype-register-input-source",
        "--register-input-source",
        "--knowtype-enable-input-source",
        "--enable-input-source",
        "--knowtype-select-input-source",
        "--select-input-source"
    ]

    static func handlesCommandLine(_ arguments: [String]) -> Bool {
        !Set(arguments.dropFirst()).isDisjoint(with: explicitCommandFlags)
    }

    static func handleCommandLineActivation(_ bundle: Bundle, arguments: [String]) -> Int32? {
        let args = Set(arguments.dropFirst())
        if args.contains("--knowtype-rime-smoke") {
            return RimeRuntimeSmoke.run()
        }
        if args.contains("--knowtype-migrate-provider-profiles") {
            return ProviderProfileStorageMigrationCommand.run()
        }
        if args.contains("--knowtype-downgrade-provider-profiles") {
            return ProviderProfileStorageMigrationCommand.downgradeForLegacyRuntime()
        }
        if args.contains("--knowtype-rollback-provider-profile-migration") {
            guard let expectedRevision = argumentValue(
                after: "--knowtype-rollback-provider-profile-migration",
                arguments: arguments
            ).flatMap(UInt64.init) else {
                fputs("provider.migration.rollback.error=expected-revision-required\n", stderr)
                return 2
            }
            return ProviderProfileStorageMigrationCommand.rollback(
                expectedCanonicalRevision: expectedRevision
            )
        }
        let shouldSwitchAway = args.contains("--knowtype-switch-away")
        let shouldPurgeLegacy = args.contains("--knowtype-purge-legacy")
        let shouldDisable = args.contains("--knowtype-disable-input-source")
        let installActivate = args.contains("--knowtype-install-activate")
        let shouldRegister = installActivate
            || args.contains("--knowtype-register-input-source")
            || args.contains("--register-input-source")
        let explicitSelect = args.contains("--knowtype-select-input-source")
            || args.contains("--select-input-source")
        let shouldEnable = installActivate
            || explicitSelect
            || args.contains("--knowtype-enable-input-source")
            || args.contains("--enable-input-source")
        let shouldSelect = installActivate
            || explicitSelect

        guard shouldSwitchAway || shouldPurgeLegacy || shouldDisable || shouldRegister || shouldEnable || shouldSelect else {
            return nil
        }
        guard bundle.bundleIdentifier == parentInputSourceID else {
            fputs("Unexpected bundle id: \(bundle.bundleIdentifier ?? "<missing>")\n", stderr)
            return 1
        }

        if shouldSwitchAway {
            switchAwayFromKnowType()
        }
        if shouldPurgeLegacy {
            purgeLegacyState(installedBundlePath: bundle.bundleURL.path)
        }
        if shouldDisable {
            disableInstalledInputSource()
        }
        if shouldRegister {
            registerInstalledBundle(bundle)
        }
        if shouldEnable {
            guard enableInstalledInputSource() else {
                return 1
            }
        }
        if shouldSelect {
            return selectVisibleMode() ? 0 : 1
        }
        return 0
    }

    private static func argumentValue(after flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private static func registerInstalledBundle(_ bundle: Bundle) {
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        inputMethodLogger.notice("Registered input source from app context with status \(status, privacy: .public)")
        print("register.status=\(status)")
        _ = TISSupport.waitForInputSource(id: parentInputSourceID, timeout: 5.0)
        _ = TISSupport.waitForInputSource(id: activeInputSourceID, timeout: 5.0)
    }

    private static func switchAwayFromKnowType() {
        guard TISSupport.currentInputSourceID()?.hasPrefix(parentInputSourceID) == true else {
            print("switch-away.status=skipped")
            return
        }
        guard let fallback = TISSupport.inputSource(id: fallbackInputSourceID) else {
            fputs("switch-away.error=fallback-missing\n", stderr)
            return
        }
        let status = TISSelectInputSource(fallback)
        if status == noErr {
            TISSupport.postNotification(kTISNotifySelectedKeyboardInputSourceChanged)
        }
        print("switch-away.status=\(status)")
        print("switch-away.current=\(TISSupport.currentInputSourceID() ?? "<unknown>")")
    }

    @discardableResult
    private static func enableInstalledInputSource() -> Bool {
        let sources = TISSupport.inputSources(bundleID: parentInputSourceID)
        let legacyModeCount = KnowTypeInputSourceIDs.legacyModes.reduce(0) { count, modeID in
            count + TISSupport.inputSources(id: modeID).count
        }
        let usesSingleInputSource = activeInputSourceID == parentInputSourceID
        let activationSources = usesSingleInputSource
            ? TISSupport.deduplicatedActivationSources(TISSupport.inputSources(id: activeInputSourceID))
            : TISSupport.deduplicatedActivationSources(
                TISSupport.inputSources(id: parentInputSourceID)
                    + TISSupport.inputSources(id: activeInputSourceID)
            )
            .sorted(by: TISSupport.enableParentBeforeModes)
        var enabledCount = 0
        var parentAnchorCount = 0
        var parentAnchorReady = usesSingleInputSource
        var modeCount = 0
        var modeReady = false
        for source in activationSources {
            let id = TISSupport.stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
            let type = TISSupport.stringProperty(source, kTISPropertyInputSourceType) ?? "<unknown>"
            let isMode = id == activeInputSourceID || TISSupport.inputModeID(source) == activeInputSourceID
            let isParentAnchor = !usesSingleInputSource && id == parentInputSourceID && !isMode
            if isParentAnchor {
                parentAnchorCount += 1
            }
            if isMode {
                modeCount += 1
            }
            guard TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnableCapable) else {
                inputMethodLogger.notice("Input source is not enable-capable id=\(id, privacy: .public) type=\(type, privacy: .public)")
                continue
            }
            var isEnabled = TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled)
            if isEnabled {
                inputMethodLogger.notice("Input source is already enabled id=\(id, privacy: .public) type=\(type, privacy: .public)")
            } else {
                let status = TISEnableInputSource(source)
                if status == noErr {
                    enabledCount += 1
                    isEnabled = true
                } else {
                    inputMethodLogger.warning("TISEnableInputSource failed id=\(id, privacy: .public) type=\(type, privacy: .public) status=\(status, privacy: .public)")
                }
            }
            if isParentAnchor, isEnabled {
                parentAnchorReady = true
            }
            if isMode,
               isEnabled,
               TISSupport.boolProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                modeReady = true
            }
        }

        inputMethodLogger.notice(
            "Input source activation complete sources=\(sources.count, privacy: .public) uniqueSources=\(activationSources.count, privacy: .public) parentAnchors=\(parentAnchorCount, privacy: .public) parentReady=\(parentAnchorReady, privacy: .public) activeModes=\(modeCount, privacy: .public) modeReady=\(modeReady, privacy: .public) legacyModes=\(legacyModeCount, privacy: .public) enabledRequests=\(enabledCount, privacy: .public)"
        )
        print("enable.sources=\(sources.count)")
        print("enable.uniqueSources=\(activationSources.count)")
        print("enable.singleSource=\(usesSingleInputSource)")
        print("enable.parentAnchors=\(parentAnchorCount)")
        print("enable.parent.ready=\(parentAnchorReady)")
        print("enable.activeModes=\(modeCount)")
        print("enable.mode.ready=\(modeReady)")
        print("enable.legacyModes=\(legacyModeCount)")
        print("enable.requests=\(enabledCount)")
        print("enable.preference.writes=skipped")
        if enabledCount > 0 {
            TISSupport.postNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)
        }
        return parentAnchorReady && modeReady
    }

    private static func disableInstalledInputSource() {
        switchAwayFromKnowType()

        let sources = TISSupport.deduplicatedActivationSources(TISSupport.inputSources(bundleID: parentInputSourceID))
            .sorted(by: TISSupport.disableModesBeforeParent)
        var disabledCount = 0
        for source in sources {
            let id = TISSupport.stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
            guard TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled) else {
                continue
            }
            let status = TISDisableInputSource(source)
            if status == noErr {
                disabledCount += 1
            } else {
                fputs("Warning: TISDisableInputSource(\(id)) returned \(status)\n", stderr)
            }
        }
        if disabledCount > 0 {
            TISSupport.postNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)
        }
        print("disable.sources=\(sources.count)")
        print("disable.requests=\(disabledCount)")
        print("disable.preference.writes=skipped")
    }

    @discardableResult
    private static func selectVisibleMode() -> Bool {
        guard let source = TISSupport.bestSelectionTarget(TISSupport.inputSources(id: activeInputSourceID)) else {
            inputMethodLogger.warning("Cannot select KnowType because input source is missing")
            fputs("select.error=input-source-missing\n", stderr)
            return false
        }
        guard TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled),
              TISSupport.boolProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            inputMethodLogger.warning("Cannot select KnowType because input source is not enabled/select-capable")
            fputs("select.error=input-source-not-selectable\n", stderr)
            return false
        }

        let status = TISSelectInputSource(source)
        if status == noErr {
            TISSupport.postNotification(kTISNotifySelectedKeyboardInputSourceChanged)
        }
        let currentID = TISSupport.waitForCurrentInputSourceID(activeInputSourceID, timeout: 2.0) ?? "<unknown>"
        inputMethodLogger.notice("Selected KnowType input source from app context status=\(status, privacy: .public) current=\(currentID, privacy: .public)")
        print("select.status=\(status)")
        print("select.current=\(currentID)")
        return status == noErr
    }

    private static func disableLegacyModes() -> Int {
        switchAwayFromLegacyModeIfNeeded()

        var disabled = 0
        for modeID in legacyModeInputSourceIDs {
            for source in TISSupport.deduplicatedActivationSources(TISSupport.inputSources(id: modeID)) {
                guard TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled) else {
                    continue
                }
                let status = TISDisableInputSource(source)
                if status == noErr {
                    disabled += 1
                } else {
                    fputs("Warning: TISDisableInputSource(\(modeID)) returned \(status)\n", stderr)
                }
            }
        }
        return disabled
    }

    private static func switchAwayFromLegacyModeIfNeeded() {
        guard let currentID = TISSupport.currentInputSourceID(),
              legacyModeInputSourceIDs.contains(currentID) else {
            return
        }
        switchAwayFromKnowType()
    }

    private static func purgeLegacyState(installedBundlePath: String) {
        let disabled = disableLegacyModes()
        let unregistered = LSSupport.unregisterStaleLaunchServices(
            path: installedBundlePath,
            bundleID: parentInputSourceID,
            warning: { fputs($0 + "\n", stderr) }
        )
        print("purge.legacy.disabled=\(disabled)")
        print("purge.legacy.preference.writes=skipped")
        print("purge.active.inputsource.id=\(activeInputSourceID)")
        print("purge.active.mode.id=\(activeInputSourceID)")
        print("purge.launchservices.unregistered=\(unregistered)")
    }
}

private enum ProviderProfileStorageMigrationCommand {
    static func run() -> Int32 {
        do {
            let result = try profileStore().migrateLegacyProfiles(
                secretStore: KeychainSecretStore()
            )
            print("provider.migration.status=\(result.status.rawValue)")
            print("provider.migration.revision=\(result.revision)")
            print("provider.migration.profiles=\(result.profileCount)")
            print("provider.migration.credentials.rekeyed=\(result.credentialsRekeyed)")
            print("provider.migration.credentials.missing=\(result.missingCredentials)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.migration.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.migration.error=unexpected\n", stderr)
            return 1
        }
    }

    static func rollback(expectedCanonicalRevision: UInt64) -> Int32 {
        do {
            let result = try profileStore().rollbackLegacyMigration(
                expectedCanonicalRevision: expectedCanonicalRevision,
                secretStore: KeychainSecretStore()
            )
            print("provider.migration.rollback=ok")
            print("provider.migration.rollback.credentials.removed=\(result.credentialsRemoved)")
            print("provider.migration.rollback.credentials.cleanupFailures=\(result.credentialCleanupFailures)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.migration.rollback.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.migration.rollback.error=unexpected\n", stderr)
            return 1
        }
    }

    static func downgradeForLegacyRuntime() -> Int32 {
        do {
            let result = try profileStore().downgradeCanonicalProfilesForLegacyRuntime()
            print("provider.storage.downgrade.status=\(result.status.rawValue)")
            print("provider.storage.downgrade.revision=\(result.revision)")
            print("provider.storage.downgrade.profiles=\(result.profileCount)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.storage.downgrade.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.storage.downgrade.error=unexpected\n", stderr)
            return 1
        }
    }

    private static func profileStore() throws -> FileProviderProfileStore {
        if let override = ProcessInfo.processInfo.environment["KNOWTYPE_APP_SUPPORT_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let directory = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return FileProviderProfileStore(
                fileURL: directory.appendingPathComponent(FileProviderProfileStore.canonicalFilename),
                legacyFileURL: directory.appendingPathComponent(FileProviderProfileStore.legacyFilename),
                legacySnapshotURL: directory.appendingPathComponent(FileProviderProfileStore.legacySnapshotFilename)
            )
        }
        return try FileProviderProfileStore.defaultStore()
    }

    private static func errorCode(_ error: ProviderProfileStoreError) -> String {
        switch error {
        case .unsupportedSchemaVersion:
            return "unsupported-schema"
        case .revisionConflict:
            return "revision-conflict"
        case .revisionOverflow:
            return "revision-overflow"
        case .lockFailed:
            return "lock-failed"
        case .migrationRequired:
            return "migration-required"
        case .canonicalFileMissing:
            return "canonical-missing"
        case .legacyWriterDetected:
            return "legacy-writer-detected"
        case .legacyChangedDuringMigration:
            return "legacy-changed"
        case .invalidMigrationCredentialReference:
            return "invalid-credential-reference"
        case .filePermissionUpdateFailed:
            return "permission-update-failed"
        case .migrationRollbackFailed:
            return "migration-rollback-failed"
        case .metadataRollbackFailed:
            return "metadata-rollback-failed"
        }
    }
}

private enum RimeRuntimeSmoke {
    static func run() -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["KNOWTYPE_RIME_ENABLED"] = "1"
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            fputs("rime.smoke=unavailable\n", stderr)
            return 1
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-smoke-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sandbox)
        }

        var engine = RimeConversionEngine(configuration: configuration)
        guard engine.process(.text("w")).handled else {
            fputs("rime.smoke=session-unavailable\n", stderr)
            return 1
        }
        guard engine.isNativeActive else {
            fputs("rime.smoke=session-unavailable\n", stderr)
            return 1
        }
        _ = engine.process(.text("o"))
        guard !engine.snapshot.candidates.isEmpty else {
            fputs("rime.smoke=no-candidates\n", stderr)
            return 1
        }
        let result = engine.process(.space)
        guard result.commitText?.isEmpty == false else {
            fputs("rime.smoke=no-commit\n", stderr)
            return 1
        }
        print("rime.smoke=ok")
        return 0
    }
}

final class KnowTypeAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? KnowTypeInputSourceIDs.parent
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? KnowTypeInputSourceIDs.connectionName
        server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        inputMethodLogger.notice(
            "KnowTypeInputMethodApp launched bundle=\(bundleIdentifier, privacy: .public) connection=\(connectionName, privacy: .public)"
        )
    }
}

let arguments = CommandLine.arguments
let startupExitCode = KnowTypeInputMethodStartupPolicy.run(
    explicitCommandRequested: TextInputSourceActivation.handlesCommandLine(arguments),
    serveInputMethod: {
        let application = NSApplication.shared
        let delegate = KnowTypeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    },
    runExplicitCommand: {
        TextInputSourceActivation.handleCommandLineActivation(Bundle.main, arguments: arguments) ?? 1
    }
)
if let startupExitCode {
    exit(startupExitCode)
}
#else
import Foundation

fputs("KnowTypeInputMethodApp requires macOS InputMethodKit.\n", stderr)
exit(1)
#endif
