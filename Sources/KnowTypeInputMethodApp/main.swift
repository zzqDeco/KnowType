#if canImport(InputMethodKit)
import AppKit
import Carbon
import InputMethodKit
import KnowTypeCore
import KnowTypeInputMethod
import KnowTypeInputSourceSupport
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
    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func handleCommandLineActivation(_ bundle: Bundle, arguments: [String]) -> Int32? {
        let args = Set(arguments.dropFirst())
        if args.contains("--knowtype-rime-smoke") {
            return RimeRuntimeSmoke.run()
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

    static func registerAndEnableInstalledBundle(_ bundle: Bundle, selectMode: Bool) {
        guard bundle.bundleIdentifier == parentInputSourceID else {
            inputMethodLogger.warning("Skipping input source activation for unexpected bundle id \(bundle.bundleIdentifier ?? "<missing>", privacy: .public)")
            return
        }

        registerInstalledBundle(bundle)
        _ = enableInstalledInputSource()
        if selectMode {
            _ = selectVisibleMode()
        }
    }

    private static func registerInstalledBundle(_ bundle: Bundle) {
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        inputMethodLogger.notice("Registered input source from app context with status \(status, privacy: .public)")
        print("register.status=\(status)")
        _ = waitForInputSource(parentInputSourceID, timeout: 5.0)
        _ = waitForInputSource(activeInputSourceID, timeout: 5.0)
    }

    private static func switchAwayFromKnowType() {
        guard currentInputSourceID()?.hasPrefix(parentInputSourceID) == true else {
            print("switch-away.status=skipped")
            return
        }
        guard let fallback = inputSource(id: fallbackInputSourceID) else {
            fputs("switch-away.error=fallback-missing\n", stderr)
            return
        }
        let status = TISSelectInputSource(fallback)
        if status == noErr {
            postTISNotification(kTISNotifySelectedKeyboardInputSourceChanged)
        }
        print("switch-away.status=\(status)")
        print("switch-away.current=\(currentInputSourceID() ?? "<unknown>")")
    }

    @discardableResult
    private static func enableInstalledInputSource() -> Bool {
        let sources = inputSources(bundleID: parentInputSourceID)
        let legacyModeCount = KnowTypeInputSourceIDs.legacyModes.reduce(0) { count, modeID in
            count + inputSources(id: modeID).count
        }
        let usesSingleInputSource = activeInputSourceID == parentInputSourceID
        let activationSources = usesSingleInputSource
            ? deduplicatedSources(inputSources(id: activeInputSourceID))
            : deduplicatedSources(inputSources(id: parentInputSourceID) + inputSources(id: activeInputSourceID))
                .sorted(by: enableParentBeforeModes)
        var enabledCount = 0
        var parentAnchorCount = 0
        var parentAnchorReady = usesSingleInputSource
        var modeCount = 0
        var modeReady = false
        for source in activationSources {
            let id = stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
            let type = stringProperty(source, kTISPropertyInputSourceType) ?? "<unknown>"
            let isMode = id == activeInputSourceID || inputModeID(source) == activeInputSourceID
            let isParentAnchor = !usesSingleInputSource && id == parentInputSourceID && !isMode
            if isParentAnchor {
                parentAnchorCount += 1
            }
            if isMode {
                modeCount += 1
            }
            guard boolProperty(source, kTISPropertyInputSourceIsEnableCapable) else {
                inputMethodLogger.notice("Input source is not enable-capable id=\(id, privacy: .public) type=\(type, privacy: .public)")
                continue
            }
            var isEnabled = boolProperty(source, kTISPropertyInputSourceIsEnabled)
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
               boolProperty(source, kTISPropertyInputSourceIsSelectCapable) {
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
            postTISNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)
        }
        return parentAnchorReady && modeReady
    }

    private static func disableInstalledInputSource() {
        switchAwayFromKnowType()

        let sources = deduplicatedSources(inputSources(bundleID: parentInputSourceID))
            .sorted(by: disableModesBeforeParent)
        var disabledCount = 0
        for source in sources {
            let id = stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
            guard boolProperty(source, kTISPropertyInputSourceIsEnabled) else {
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
            postTISNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)
        }
        print("disable.sources=\(sources.count)")
        print("disable.requests=\(disabledCount)")
        print("disable.preference.writes=skipped")
    }

    private static func inputSources(bundleID: String) -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func inputSources(id: String) -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func inputSource(id: String) -> TISInputSource? {
        inputSources(id: id).first
    }

    private static func postTISNotification(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    private static func deduplicatedSources(_ sources: [TISInputSource]) -> [TISInputSource] {
        var orderedSignatures: [String] = []
        var sourcesBySignature: [String: TISInputSource] = [:]

        for source in sources {
            let signature = sourceSignature(source)
            guard let existing = sourcesBySignature[signature] else {
                orderedSignatures.append(signature)
                sourcesBySignature[signature] = source
                continue
            }
            if sourceIsBetterActivationTarget(source, than: existing) {
                sourcesBySignature[signature] = source
            }
        }

        return orderedSignatures.compactMap { sourcesBySignature[$0] }
    }

    private static func sourceSignature(_ source: TISInputSource) -> String {
        let id = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        let mode = inputModeID(source) ?? ""
        let type = stringProperty(source, kTISPropertyInputSourceType) ?? ""
        return "\(id)|\(mode)|\(type)"
    }

    private static func sourceIsBetterActivationTarget(_ candidate: TISInputSource, than existing: TISInputSource) -> Bool {
        let candidateEnableCapable = boolProperty(candidate, kTISPropertyInputSourceIsEnableCapable)
        let existingEnableCapable = boolProperty(existing, kTISPropertyInputSourceIsEnableCapable)
        if candidateEnableCapable != existingEnableCapable {
            return candidateEnableCapable
        }

        let candidateSelectCapable = boolProperty(candidate, kTISPropertyInputSourceIsSelectCapable)
        let existingSelectCapable = boolProperty(existing, kTISPropertyInputSourceIsSelectCapable)
        if candidateSelectCapable != existingSelectCapable {
            return candidateSelectCapable
        }

        let candidateEnabled = boolProperty(candidate, kTISPropertyInputSourceIsEnabled)
        let existingEnabled = boolProperty(existing, kTISPropertyInputSourceIsEnabled)
        if candidateEnabled != existingEnabled {
            return candidateEnabled
        }

        return false
    }

    private static func enableParentBeforeModes(_ lhs: TISInputSource, _ rhs: TISInputSource) -> Bool {
        let lhsIsMode = inputModeID(lhs) != nil
        let rhsIsMode = inputModeID(rhs) != nil
        return !lhsIsMode && rhsIsMode
    }

    private static func disableModesBeforeParent(_ lhs: TISInputSource, _ rhs: TISInputSource) -> Bool {
        let lhsIsMode = inputModeID(lhs) != nil
        let rhsIsMode = inputModeID(rhs) != nil
        return lhsIsMode && !rhsIsMode
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func inputModeID(_ source: TISInputSource) -> String? {
        stringProperty(source, kTISPropertyInputModeID)
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return false
        }
        return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
    }

    @discardableResult
    private static func selectVisibleMode() -> Bool {
        guard let source = bestSelectionTarget(inputSources(id: activeInputSourceID)) else {
            inputMethodLogger.warning("Cannot select KnowType because input source is missing")
            fputs("select.error=input-source-missing\n", stderr)
            return false
        }
        guard boolProperty(source, kTISPropertyInputSourceIsEnabled),
              boolProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            inputMethodLogger.warning("Cannot select KnowType because input source is not enabled/select-capable")
            fputs("select.error=input-source-not-selectable\n", stderr)
            return false
        }

        let status = TISSelectInputSource(source)
        if status == noErr {
            postTISNotification(kTISNotifySelectedKeyboardInputSourceChanged)
        }
        let currentID = waitForCurrentInputSourceID(activeInputSourceID, timeout: 2.0) ?? "<unknown>"
        inputMethodLogger.notice("Selected KnowType input source from app context status=\(status, privacy: .public) current=\(currentID, privacy: .public)")
        print("select.status=\(status)")
        print("select.current=\(currentID)")
        return status == noErr && currentID == activeInputSourceID
    }

    private static func bestSelectionTarget(_ sources: [TISInputSource]) -> TISInputSource? {
        sources.reduce(nil) { best, source in
            guard let best else {
                return source
            }
            return sourceIsBetterSelectionTarget(source, than: best) ? source : best
        }
    }

    private static func waitForInputSource(_ id: String, timeout: TimeInterval) -> TISInputSource? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let source = inputSource(id: id) {
                return source
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return inputSource(id: id)
    }

    private static func waitForCurrentInputSourceID(_ id: String, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var currentID = currentInputSourceID()
        while currentID != id && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            currentID = currentInputSourceID()
        }
        return currentID
    }

    private static func sourceIsBetterSelectionTarget(_ candidate: TISInputSource, than existing: TISInputSource) -> Bool {
        let candidateSelectCapable = boolProperty(candidate, kTISPropertyInputSourceIsSelectCapable)
        let existingSelectCapable = boolProperty(existing, kTISPropertyInputSourceIsSelectCapable)
        if candidateSelectCapable != existingSelectCapable {
            return candidateSelectCapable
        }

        let candidateEnabled = boolProperty(candidate, kTISPropertyInputSourceIsEnabled)
        let existingEnabled = boolProperty(existing, kTISPropertyInputSourceIsEnabled)
        if candidateEnabled != existingEnabled {
            return candidateEnabled
        }

        let candidateEnableCapable = boolProperty(candidate, kTISPropertyInputSourceIsEnableCapable)
        let existingEnableCapable = boolProperty(existing, kTISPropertyInputSourceIsEnableCapable)
        if candidateEnableCapable != existingEnableCapable {
            return candidateEnableCapable
        }

        return false
    }

    private static func bestActivationTarget(_ sources: [TISInputSource]) -> TISInputSource? {
        sources.reduce(nil) { best, source in
            guard let best else {
                return source
            }
            return sourceIsBetterActivationTarget(source, than: best) ? source : best
        }
    }

    private static func currentInputSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(current, kTISPropertyInputSourceID)
    }

    @discardableResult
    private static func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return (1, "")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func stripLSRegisterSuffix(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+\(0x[0-9A-Fa-f]+\)$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func expandedPath(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + "/" + path.dropFirst(2)
        }
        return path
    }

    private static func canonicalBundlePath(_ path: String) -> String {
        let expanded = expandedPath(stripLSRegisterSuffix(path))
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        }
        return expanded
    }

    private static func launchServicesPaths(bundleID: String) -> [String] {
        guard FileManager.default.isExecutableFile(atPath: lsregisterPath) else {
            return []
        }
        let result = runProcess(lsregisterPath, ["-dump"])
        guard result.status == 0 else {
            return []
        }

        var paths: [String] = []
        var currentPath = ""
        for rawLine in result.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("bundle id:") {
                currentPath = ""
            } else if line.hasPrefix("path:") {
                currentPath = line.replacingOccurrences(of: "path:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("identifier:") {
                let identifier = stripLSRegisterSuffix(
                    line.replacingOccurrences(of: "identifier:", with: "").trimmingCharacters(in: .whitespaces)
                )
                if identifier == bundleID, !currentPath.isEmpty {
                    paths.append(currentPath)
                    currentPath = ""
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    private static func unregisterStaleLaunchServices(installedBundlePath: String) -> Int {
        guard FileManager.default.isExecutableFile(atPath: lsregisterPath) else {
            fputs("Warning: lsregister command is unavailable.\n", stderr)
            return 0
        }

        let canonicalTarget = canonicalBundlePath(installedBundlePath)
        var unregistered = 0
        for candidate in launchServicesPaths(bundleID: parentInputSourceID) {
            let canonicalCandidate = canonicalBundlePath(candidate)
            guard canonicalCandidate != canonicalTarget else {
                continue
            }
            let unregisterPath = expandedPath(stripLSRegisterSuffix(candidate))
            let result = runProcess(lsregisterPath, ["-u", unregisterPath])
            if result.status == 0 {
                unregistered += 1
            } else if !FileManager.default.fileExists(atPath: unregisterPath) {
                _ = runProcess(lsregisterPath, ["-gc"])
            } else {
                fputs("Warning: lsregister -u failed for \(unregisterPath)\n", stderr)
            }
        }
        return unregistered
    }

    private static func disableLegacyModes() -> Int {
        switchAwayFromLegacyModeIfNeeded()

        var disabled = 0
        for modeID in legacyModeInputSourceIDs {
            for source in deduplicatedSources(inputSources(id: modeID)) {
                guard boolProperty(source, kTISPropertyInputSourceIsEnabled) else {
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
        guard let currentID = currentInputSourceID(),
              legacyModeInputSourceIDs.contains(currentID) else {
            return
        }
        switchAwayFromKnowType()
    }

    private static func purgeLegacyState(installedBundlePath: String) {
        let disabled = disableLegacyModes()
        let unregistered = unregisterStaleLaunchServices(installedBundlePath: installedBundlePath)
        print("purge.legacy.disabled=\(disabled)")
        print("purge.legacy.preference.writes=skipped")
        print("purge.active.inputsource.id=\(activeInputSourceID)")
        print("purge.active.mode.id=\(activeInputSourceID)")
        print("purge.launchservices.unregistered=\(unregistered)")
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
        let shouldSelectMode = CommandLine.arguments.contains("--knowtype-install-activate")
        TextInputSourceActivation.registerAndEnableInstalledBundle(bundle, selectMode: shouldSelectMode)
    }
}

if let exitCode = TextInputSourceActivation.handleCommandLineActivation(Bundle.main, arguments: CommandLine.arguments) {
    exit(exitCode)
}

let application = NSApplication.shared
let delegate = KnowTypeAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
#else
import Foundation

fputs("KnowTypeInputMethodApp requires macOS InputMethodKit.\n", stderr)
exit(1)
#endif
