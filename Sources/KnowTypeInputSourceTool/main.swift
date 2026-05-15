import Carbon
import Foundation

private let defaultParentID = "com.knowtype.inputmethod.KnowType"
private let defaultModeID = "com.knowtype.inputmethod.KnowType.Mode"
private let defaultFallbackID = "com.apple.keylayout.ABC"

private enum ExitCode: Int32 {
    case ok = 0
    case usage = 2
    case failure = 1
}

private func usage() -> Never {
    fputs(
        """
        Usage:
          knowtype-inputsource-tool status [--parent-id ID] [--mode-id ID]
          knowtype-inputsource-tool dump [--bundle-id ID]
          knowtype-inputsource-tool disable [--bundle-id ID]
          knowtype-inputsource-tool switch-away [--prefix ID_PREFIX] [--fallback-id ID]
          knowtype-inputsource-tool register --path PATH [--parent-id ID] [--mode-id ID] [--select]
          knowtype-inputsource-tool select [--parent-id ID] [--mode-id ID] [--require-selected]

        This helper performs KnowType Text Input Source registration and selection
        without routing macOS permission prompts through swift-frontend.

        """,
        stderr
    )
    exit(ExitCode.usage.rawValue)
}

private struct Arguments {
    var values: [String]

    mutating func flag(_ name: String) -> Bool {
        guard let index = values.firstIndex(of: name) else {
            return false
        }
        values.remove(at: index)
        return true
    }

    mutating func option(_ name: String, default defaultValue: String? = nil) -> String? {
        guard let index = values.firstIndex(of: name) else {
            return defaultValue
        }
        let valueIndex = values.index(after: index)
        guard valueIndex < values.endIndex else {
            usage()
        }
        let value = values[valueIndex]
        values.remove(at: valueIndex)
        values.remove(at: index)
        return value
    }

    func ensureConsumed() {
        if !values.isEmpty {
            usage()
        }
    }
}

private func stringProperty(_ source: TISInputSource?, _ key: CFString) -> String? {
    guard let source, let raw = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

private func boolProperty(_ source: TISInputSource?, _ key: CFString) -> Bool {
    guard let source, let raw = TISGetInputSourceProperty(source, key) else {
        return false
    }
    return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
}

private func inputSources(id: String) -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
}

private func inputSources(bundleID: String) -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
}

private func hitoolboxPreferenceArray(_ key: String) -> [[String: Any]] {
    CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
    return CFPreferencesCopyAppValue(key as CFString, "com.apple.HIToolbox" as CFString) as? [[String: Any]] ?? []
}

private func hitoolboxPreferencesContain(bundleID: String, modeID: String, key: String) -> Bool {
    hitoolboxPreferenceArray(key).contains { entry in
        entry["Bundle ID"] as? String == bundleID &&
            entry["Input Mode"] as? String == modeID &&
            entry["InputSourceKind"] as? String == "Input Mode"
    }
}

private func hitoolboxSelectedModeID() -> String? {
    hitoolboxPreferenceArray("AppleSelectedInputSources")
        .first { $0["InputSourceKind"] as? String == "Input Mode" }?["Input Mode"] as? String
}

private func inputSource(id: String) -> TISInputSource? {
    inputSources(id: id).first
}

private func enableInputSource(_ source: TISInputSource, label: String) {
    let status = TISEnableInputSource(source)
    if status != noErr {
        fputs("Warning: TISEnableInputSource(\(label)) returned \(status)\n", stderr)
    }
}

private func disableInputSources(bundleID: String) {
    let sources = inputSources(bundleID: bundleID)
    var disabledCount = 0
    for source in sources.sorted(by: { lhs, rhs in
        let lhsIsMode = stringProperty(lhs, kTISPropertyInputModeID) != nil
        let rhsIsMode = stringProperty(rhs, kTISPropertyInputModeID) != nil
        return lhsIsMode && !rhsIsMode
    }) {
        let id = stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
        let status = TISDisableInputSource(source)
        if status == noErr {
            disabledCount += 1
        } else {
            fputs("Warning: TISDisableInputSource(\(id)) returned \(status)\n", stderr)
        }
    }
    print("disabled.bundle=\(bundleID)")
    print("disabled.count=\(disabledCount)")
}

private func currentInputSourceID() -> String? {
    stringProperty(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), kTISPropertyInputSourceID)
}

private func printStatus(parentID: String, modeID: String) {
    let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    let currentID = stringProperty(current, kTISPropertyInputSourceID) ?? ""
    let parent = inputSource(id: parentID)
    let mode = inputSource(id: modeID)

    print("current.id=\(currentID)")
    print("parent.found=\(parent != nil)")
    print("parent.enabled=\(boolProperty(parent, kTISPropertyInputSourceIsEnabled))")
    print("parent.selectCapable=\(boolProperty(parent, kTISPropertyInputSourceIsSelectCapable))")
    print("parent.type=\(stringProperty(parent, kTISPropertyInputSourceType) ?? "")")
    print("mode.found=\(mode != nil)")
    print("mode.enabled=\(boolProperty(mode, kTISPropertyInputSourceIsEnabled))")
    print("mode.selectCapable=\(boolProperty(mode, kTISPropertyInputSourceIsSelectCapable))")
    print("mode.type=\(stringProperty(mode, kTISPropertyInputSourceType) ?? "")")
    print("mode.selected=\(currentID == modeID)")
    print("mode.name=\(stringProperty(mode, kTISPropertyLocalizedName) ?? "")")
    print("mode.count=\(inputSources(id: modeID).count)")
    print("preference.selected.mode=\(hitoolboxSelectedModeID() ?? "")")
    print("preference.selected.knowtype=\(hitoolboxPreferencesContain(bundleID: parentID, modeID: modeID, key: "AppleSelectedInputSources"))")
    print("preference.enabled.knowtype=\(hitoolboxPreferencesContain(bundleID: parentID, modeID: modeID, key: "AppleEnabledInputSources"))")
}

private func printDump(bundleID: String) {
    let sources = inputSources(bundleID: bundleID)
    print("bundle.id=\(bundleID)")
    print("bundle.count=\(sources.count)")

    for (index, source) in sources.enumerated() {
        let id = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        let modeID = stringProperty(source, kTISPropertyInputModeID) ?? ""
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? ""
        let category = stringProperty(source, kTISPropertyInputSourceCategory) ?? ""
        let type = stringProperty(source, kTISPropertyInputSourceType) ?? ""

        print("source.\(index).id=\(id)")
        print("source.\(index).mode=\(modeID)")
        print("source.\(index).name=\(name)")
        print("source.\(index).category=\(category)")
        print("source.\(index).type=\(type)")
        print("source.\(index).enabled=\(boolProperty(source, kTISPropertyInputSourceIsEnabled))")
        print("source.\(index).enableCapable=\(boolProperty(source, kTISPropertyInputSourceIsEnableCapable))")
        print("source.\(index).selectCapable=\(boolProperty(source, kTISPropertyInputSourceIsSelectCapable))")
        print("source.\(index).asciiCapable=\(boolProperty(source, kTISPropertyInputSourceIsASCIICapable))")
    }
}

private func switchAway(prefix: String, fallbackID: String) {
    let currentID = currentInputSourceID()
    guard currentID?.hasPrefix(prefix) == true else {
        return
    }
    if let fallback = inputSource(id: fallbackID) {
        TISSelectInputSource(fallback)
    }
}

private func register(path: String, parentID: String, modeID: String, select: Bool) {
    let targetURL = URL(fileURLWithPath: path) as CFURL
    let registerStatus = TISRegisterInputSource(targetURL)
    if registerStatus != noErr {
        fputs("Warning: TISRegisterInputSource returned \(registerStatus)\n", stderr)
    }

    if let parent = inputSource(id: parentID) {
        enableInputSource(parent, label: "parent")
    }

    let deadline = Date().addingTimeInterval(5.0)
    while Date() < deadline {
        if boolProperty(inputSource(id: parentID), kTISPropertyInputSourceIsEnabled) {
            break
        }
        Thread.sleep(forTimeInterval: 0.25)
    }

    guard let mode = inputSource(id: modeID) else {
        fputs("Warning: KnowType input mode was not found after registration.\n", stderr)
        exit(ExitCode.failure.rawValue)
    }

    enableInputSource(mode, label: "mode")

    if select {
        selectMode(parentID: parentID, modeID: modeID, requireSelected: false)
    }
}

private func selectMode(parentID: String, modeID: String, requireSelected: Bool) {
    if let parent = inputSource(id: parentID) {
        enableInputSource(parent, label: "parent")
    }

    guard let mode = inputSource(id: modeID) else {
        fputs("KnowType input mode was not found. Run ./scripts/install-inputmethod.sh first.\n", stderr)
        exit(ExitCode.failure.rawValue)
    }

    enableInputSource(mode, label: "mode")

    let selectStatus = TISSelectInputSource(mode)
    if selectStatus == noErr {
        print("Requested KnowType input source selection: \(modeID)")
    } else {
        fputs("TISSelectInputSource(mode) returned \(selectStatus). Enable or select KnowType from System Settings if macOS did not switch automatically.\n", stderr)
        exit(Int32(selectStatus))
    }

    let deadline = Date().addingTimeInterval(2.0)
    var currentID = currentInputSourceID()
    while currentID != modeID && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
        currentID = currentInputSourceID()
    }

    if currentID == modeID {
        print("Verified KnowType only in this helper-local TIS context: \(modeID)")
        print("The macOS menu bar or another app may still use a different input source.")
        print("Select KnowType in the target text app, then type a real probe before accepting manual typing.")
    } else {
        let observed = currentID ?? "<unavailable>"
        fputs("Warning: this preflight TIS context is \(observed), not \(modeID). Activate the target text app, rerun this helper, then type a real probe in that app.\n", stderr)
        if requireSelected {
            exit(ExitCode.failure.rawValue)
        }
    }
}

private var arguments = Arguments(values: Array(CommandLine.arguments.dropFirst()))
guard !arguments.values.isEmpty else {
    usage()
}

let command = arguments.values.removeFirst()
switch command {
case "status":
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    arguments.ensureConsumed()
    printStatus(parentID: parentID, modeID: modeID)
case "dump":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    arguments.ensureConsumed()
    printDump(bundleID: bundleID)
case "disable":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    arguments.ensureConsumed()
    disableInputSources(bundleID: bundleID)
case "switch-away":
    let prefix = arguments.option("--prefix", default: defaultParentID) ?? defaultParentID
    let fallbackID = arguments.option("--fallback-id", default: defaultFallbackID) ?? defaultFallbackID
    arguments.ensureConsumed()
    switchAway(prefix: prefix, fallbackID: fallbackID)
case "register":
    guard let path = arguments.option("--path") else {
        usage()
    }
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let select = arguments.flag("--select")
    arguments.ensureConsumed()
    register(path: path, parentID: parentID, modeID: modeID, select: select)
case "select":
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let requireSelected = arguments.flag("--require-selected")
    arguments.ensureConsumed()
    selectMode(parentID: parentID, modeID: modeID, requireSelected: requireSelected)
default:
    usage()
}
