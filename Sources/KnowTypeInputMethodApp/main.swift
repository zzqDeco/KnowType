#if canImport(InputMethodKit)
import AppKit
import Carbon
import InputMethodKit
import KnowTypeCore
import KnowTypeInputMethod
import OSLog

private let inputMethodLogger = Logger(
    subsystem: "com.knowtype.inputmethod.KnowType",
    category: "input-method-app"
)

private enum TextInputSourceActivation {
    private static let parentInputSourceID = "com.knowtype.inputmethod.KnowType"
    private static let modeInputSourceID = "com.knowtype.inputmethod.KnowType.Mode"

    static func registerAndEnableInstalledBundle(_ bundle: Bundle, selectMode: Bool) {
        guard bundle.bundleIdentifier == parentInputSourceID else {
            inputMethodLogger.warning("Skipping input source activation for unexpected bundle id \(bundle.bundleIdentifier ?? "<missing>", privacy: .public)")
            return
        }

        var sources = inputSources(bundleID: parentInputSourceID)
        if sources.isEmpty {
            let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
            inputMethodLogger.notice("Registered input source from app context with status \(status, privacy: .public)")
            sources = inputSources(bundleID: parentInputSourceID)
        } else {
            inputMethodLogger.notice("Using existing input source registration count=\(sources.count, privacy: .public)")
        }

        let activationSources = deduplicatedSources(sources).sorted(by: enableParentBeforeModes)
        var enabledCount = 0
        var modeCount = 0
        for source in activationSources {
            let id = stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
            let type = stringProperty(source, kTISPropertyInputSourceType) ?? "<unknown>"
            let isMode = id == modeInputSourceID || inputModeID(source) == modeInputSourceID
            if isMode {
                modeCount += 1
            }
            guard boolProperty(source, kTISPropertyInputSourceIsEnableCapable) else {
                inputMethodLogger.notice("Input source is not enable-capable id=\(id, privacy: .public) type=\(type, privacy: .public)")
                continue
            }
            let status = TISEnableInputSource(source)
            if status == noErr {
                enabledCount += 1
            } else {
                inputMethodLogger.warning("TISEnableInputSource failed id=\(id, privacy: .public) type=\(type, privacy: .public) status=\(status, privacy: .public)")
            }
        }

        inputMethodLogger.notice(
            "Input source activation complete sources=\(sources.count, privacy: .public) uniqueSources=\(activationSources.count, privacy: .public) modes=\(modeCount, privacy: .public) enabledRequests=\(enabledCount, privacy: .public)"
        )

        if selectMode {
            selectVisibleMode()
        }
    }

    private static func inputSources(bundleID: String) -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func inputSources(id: String) -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
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

    private static func selectVisibleMode() {
        guard let mode = inputSources(id: modeInputSourceID).first else {
            inputMethodLogger.warning("Cannot select KnowType because mode source is missing")
            return
        }
        guard boolProperty(mode, kTISPropertyInputSourceIsEnabled),
              boolProperty(mode, kTISPropertyInputSourceIsSelectCapable) else {
            inputMethodLogger.warning("Cannot select KnowType because mode is not enabled/select-capable")
            return
        }

        let status = TISSelectInputSource(mode)
        let currentID = currentInputSourceID() ?? "<unknown>"
        inputMethodLogger.notice("Selected KnowType mode from app context status=\(status, privacy: .public) current=\(currentID, privacy: .public)")
    }

    private static func currentInputSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(current, kTISPropertyInputSourceID)
    }
}

final class KnowTypeAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.knowtype.inputmethod.KnowType"
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? "com.knowtype.inputmethod.KnowType_Connection"
        server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        inputMethodLogger.notice(
            "KnowTypeInputMethodApp launched bundle=\(bundleIdentifier, privacy: .public) connection=\(connectionName, privacy: .public)"
        )
        Task.detached(priority: .utility) {
            let preferences = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore().loadPreferences()
            InputMethodLexiconRuntime.prewarmDefaultEngine(scheme: preferences.inputScheme)
        }
        let shouldSelectMode = CommandLine.arguments.contains("--knowtype-install-activate")
        if shouldSelectMode {
            NSApp.activate(ignoringOtherApps: true)
        }
        TextInputSourceActivation.registerAndEnableInstalledBundle(bundle, selectMode: shouldSelectMode)
    }
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
