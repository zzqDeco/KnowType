import Carbon
import Foundation
import KnowTypeInputSourceSupport
import KnowTypeProviders

private let defaultParentID = KnowTypeInputSourceIDs.parent
private let defaultModeID = KnowTypeInputSourceIDs.activeMode
private let defaultLegacyModeIDs = KnowTypeInputSourceIDs.legacyModes
private let defaultFallbackID = KnowTypeInputSourceIDs.fallback
private typealias LSSupport = KnowTypeLaunchServicesSupport
private typealias TISSupport = KnowTypeTISSupport

private enum ExitCode: Int32 {
    case ok = 0
    case usage = 2
    case failure = 1
}

private func usage() -> Never {
    fputs(
        """
        Usage:
          knowtype-inputsource-tool status [--parent-id ID] [--mode-id ID] [--legacy-mode-id ID]
          knowtype-inputsource-tool dump [--bundle-id ID]
          knowtype-inputsource-tool disable [--bundle-id ID]
          knowtype-inputsource-tool inspect-preferences [--bundle-id ID] [--mode-id ID] [--legacy-mode-id ID]
          knowtype-inputsource-tool dedupe-preferences [--bundle-id ID] [--mode-id ID] [--legacy-mode-id ID]
          knowtype-inputsource-tool repair-preferences [--bundle-id ID] [--mode-id ID] [--legacy-mode-id ID] [--include-history] [--include-selected] [--add-active] [--remove-parent-anchor] [--legacy-parent-anchor]
          knowtype-inputsource-tool switch-away [--prefix ID_PREFIX] [--fallback-id ID] [--parent-id ID] [--mode-id ID] [--legacy-mode-id ID]
          knowtype-inputsource-tool register --path PATH [--parent-id ID] [--mode-id ID] [--select]
          knowtype-inputsource-tool bootstrap --path PATH [--parent-id ID] [--mode-id ID] [--legacy-mode-id ID] [--select] [--require-selected]
          knowtype-inputsource-tool purge-legacy --path PATH [--parent-id ID] [--mode-id ID] [--legacy-mode-id ID]
          knowtype-inputsource-tool select [--parent-id ID] [--mode-id ID] [--require-selected]
          knowtype-inputsource-tool migrate-provider-profiles
          knowtype-inputsource-tool downgrade-provider-profiles
          knowtype-inputsource-tool rollback-provider-profile-migration --expected-revision REVISION

        This helper performs KnowType Text Input Source diagnostics and legacy
        cleanup through TIS APIs. switch-away can clear stale KnowType selected
        preferences before install so macOS does not relaunch the host.
        Preference inspection is read-only; repair-preferences is an explicit local development cleanup
        for stale selected/history parent rows or .Mode rows in protected input-source preferences.
        Use --add-active only for local cache repair; it writes the required
        parent anchor plus visible .Hans input mode to enabled preferences, while
        history repair keeps KnowType available and selected repair is reserved
        for explicit verified selection. .Mode is treated as legacy cleanup.
        --remove-parent-anchor is an explicit uninstall cleanup mode for removing
        enabled KnowType rows after the bundle is gone.
        --legacy-parent-anchor is accepted as a deprecated compatibility no-op.

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

    mutating func options(_ name: String) -> [String] {
        var result: [String] = []
        while let index = values.firstIndex(of: name) {
            let valueIndex = values.index(after: index)
            guard valueIndex < values.endIndex else {
                usage()
            }
            result.append(values[valueIndex])
            values.remove(at: valueIndex)
            values.remove(at: index)
        }
        return result
    }

    func ensureConsumed() {
        if !values.isEmpty {
            usage()
        }
    }
}

private func legacyModeIDs(from arguments: inout Arguments) -> [String] {
    let explicit = arguments.options("--legacy-mode-id")
    return explicit.isEmpty ? defaultLegacyModeIDs : explicit
}

private func preferenceArray(_ key: String, domain: String) -> [[String: Any]] {
    if domain == "com.apple.inputsources",
       let direct = directUserPreferenceArray(key: key, domain: domain) {
        return direct
    }
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [[String: Any]] ?? []
}

private func userPreferencePlistURL(domain: String) -> URL {
    URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Preferences")
        .appendingPathComponent("\(domain).plist")
}

private func directUserPreferenceDictionary(domain: String) -> [String: Any] {
    let url = userPreferencePlistURL(domain: domain)
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          let dictionary = plist as? [String: Any] else {
        return [:]
    }
    return dictionary
}

private func directUserPreferenceArray(key: String, domain: String) -> [[String: Any]]? {
    directUserPreferenceDictionary(domain: domain)[key] as? [[String: Any]]
}

private func modePreferenceEntry(bundleID: String, modeID: String) -> [String: String] {
    [
        "Bundle ID": bundleID,
        "Input Mode": modeID,
        "InputSourceKind": "Input Mode"
    ]
}

private func parentPreferenceEntry(bundleID: String) -> [String: String] {
    [
        "Bundle ID": bundleID,
        "InputSourceKind": "Keyboard Input Method"
    ]
}

private func activePreferenceEntry(bundleID: String, modeID: String) -> [String: String] {
    modeID == bundleID
        ? parentPreferenceEntry(bundleID: bundleID)
        : modePreferenceEntry(bundleID: bundleID, modeID: modeID)
}

private func preferenceEntryMatches(_ entry: [String: Any], target: [String: String]) -> Bool {
    target.allSatisfy { key, value in
        entry[key] as? String == value
    }
}

private func preferencesContainEntry(_ entries: [[String: Any]], target: [String: String]) -> Bool {
    entries.contains { preferenceEntryMatches($0, target: target) }
}

private func inputSourcePreferenceSignature(_ entry: [String: Any]) -> String {
    [
        entry["InputSourceKind"] as? String ?? "",
        entry["Bundle ID"] as? String ?? "",
        entry["Input Mode"] as? String ?? "",
        String(describing: entry["KeyboardLayout ID"] ?? ""),
        entry["KeyboardLayout Name"] as? String ?? ""
    ].joined(separator: "|")
}

private func isKnowTypePreferenceEntry(_ entry: [String: Any], bundleID: String, modeIDs: Set<String>) -> Bool {
    guard entry["Bundle ID"] as? String == bundleID else {
        return false
    }
    let kind = entry["InputSourceKind"] as? String
    if kind == "Keyboard Input Method" {
        return true
    }
    guard kind == "Input Mode", let inputMode = entry["Input Mode"] as? String else {
        return false
    }
    return modeIDs.isEmpty || modeIDs.contains(inputMode)
}

private func isLegacyModePreferenceEntry(_ entry: [String: Any], bundleID: String, legacyModeIDs: Set<String>) -> Bool {
    guard entry["Bundle ID"] as? String == bundleID,
          entry["InputSourceKind"] as? String == "Input Mode",
          let inputMode = entry["Input Mode"] as? String else {
        return false
    }
    return legacyModeIDs.contains(inputMode)
}

private func isStalePreferenceEntry(
    _ entry: [String: Any],
    bundleID: String,
    modeID: String,
    legacyModeIDs: Set<String>,
    removeParent: Bool
) -> Bool {
    if removeParent {
        return isKnowTypePreferenceEntry(
            entry,
            bundleID: bundleID,
            modeIDs: Set([modeID] + Array(legacyModeIDs))
        )
    }
    return isLegacyModePreferenceEntry(entry, bundleID: bundleID, legacyModeIDs: legacyModeIDs)
}

private func preferenceDuplicateCount(
    _ entries: [[String: Any]],
    bundleID: String,
    modeIDs: Set<String>
) -> Int {
    var seen = Set<String>()
    var removed = 0

    for entry in entries {
        guard isKnowTypePreferenceEntry(entry, bundleID: bundleID, modeIDs: modeIDs) else {
            continue
        }
        let signature = inputSourcePreferenceSignature(entry)
        if !seen.insert(signature).inserted {
            removed += 1
        }
    }

    return removed
}

private func inputModePreferenceCount(
    _ entries: [[String: Any]],
    bundleID: String,
    modeIDs: Set<String>
) -> Int {
    entries.filter { entry in
        guard entry["Bundle ID"] as? String == bundleID else {
            return false
        }
        if entry["InputSourceKind"] as? String == "Keyboard Input Method" {
            return modeIDs.contains(bundleID)
        }
        return entry["InputSourceKind"] as? String == "Input Mode" &&
            modeIDs.contains(entry["Input Mode"] as? String ?? "")
    }.count
}

private func preferencesContainInputMode(bundleID: String, modeID: String, domain: String, key: String) -> Bool {
    preferencesContainEntry(
        preferenceArray(key, domain: domain),
        target: activePreferenceEntry(bundleID: bundleID, modeID: modeID)
    )
}

private func preferencesContainAnyInputMode(bundleID: String, modeIDs: [String], domain: String, key: String) -> Bool {
    modeIDs.contains { modeID in
        preferencesContainInputMode(bundleID: bundleID, modeID: modeID, domain: domain, key: key)
    }
}

private func hitoolboxSelectedModeID() -> String? {
    for entry in preferenceArray("AppleSelectedInputSources", domain: "com.apple.HIToolbox") {
        if entry["InputSourceKind"] as? String == "Input Mode",
           let mode = entry["Input Mode"] as? String {
            return mode
        }
        if entry["InputSourceKind"] as? String == "Keyboard Input Method",
           let bundle = entry["Bundle ID"] as? String {
            return bundle
        }
    }
    return nil
}

@discardableResult
private func enableInputSource(_ source: TISInputSource, label: String) -> Bool {
    if TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled) {
        return true
    }
    let status = TISEnableInputSource(source)
    if status != noErr {
        fputs("Warning: TISEnableInputSource(\(label)) returned \(status)\n", stderr)
        return false
    }
    return true
}

private func disableInputSources(bundleID: String) {
    let sources = TISSupport.inputSources(bundleID: bundleID)
    var disabledCount = 0
    for source in sources.sorted(by: TISSupport.disableModesBeforeParent) {
        let id = TISSupport.stringProperty(source, kTISPropertyInputSourceID) ?? "<unknown>"
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

private func inspectPreferences(bundleID: String, modeIDs: Set<String>) {
    let targets = [
        ("com.apple.HIToolbox", "AppleEnabledInputSources"),
        ("com.apple.HIToolbox", "AppleSelectedInputSources"),
        ("com.apple.HIToolbox", "AppleInputSourceHistory"),
        ("com.apple.inputsources", "AppleEnabledThirdPartyInputSources")
    ]

    var totalDuplicates = 0
    for (domain, key) in targets {
        let current = preferenceArray(key, domain: domain)
        let duplicateCount = preferenceDuplicateCount(current, bundleID: bundleID, modeIDs: modeIDs)
        let modeCount = inputModePreferenceCount(current, bundleID: bundleID, modeIDs: modeIDs)
        totalDuplicates += duplicateCount
        print("preference.\(domain).\(key).knowtype.mode.count=\(modeCount)")
        print("preference.\(domain).\(key).duplicate.count=\(duplicateCount)")
    }
    print("preference.duplicate.total=\(totalDuplicates)")
    print("preference.writes=skipped")
}

private struct PreferenceRepairResult {
    var domain: String
    var key: String
    var removed: Int
    var added: Int
    var changed: Bool
}

private enum ActivePreferencePlacement {
    case prepend
    case append
    case afterFirstRetained
}

private func plistEntriesAreEqual(_ lhs: [[String: Any]], _ rhs: [[String: Any]]) -> Bool {
    NSArray(array: lhs).isEqual(NSArray(array: rhs))
}

private func repairPreferenceEntries(
    _ entries: [[String: Any]],
    bundleID: String,
    modeID: String,
    legacyModeIDs: [String],
    removeParent: Bool,
    addParent: Bool,
    activePlacement: ActivePreferencePlacement,
    addActive: Bool
) -> (entries: [[String: Any]], removed: Int, added: Int, changed: Bool) {
    let knowTypeModeIDs = Set([modeID] + legacyModeIDs)
    let legacyModeIDSet = Set(legacyModeIDs)
    var retained: [[String: Any]] = []
    var removed = 0

    for entry in entries {
        let shouldRemove = addActive
            ? isKnowTypePreferenceEntry(entry, bundleID: bundleID, modeIDs: knowTypeModeIDs)
            : isStalePreferenceEntry(
                entry,
                bundleID: bundleID,
                modeID: modeID,
                legacyModeIDs: legacyModeIDSet,
                removeParent: removeParent
            )
        if shouldRemove {
            removed += 1
        } else {
            retained.append(entry)
        }
    }

    var repaired = retained
    var added = 0
    if addActive {
        let activeEntry = activePreferenceEntry(bundleID: bundleID, modeID: modeID)
        var entriesToAdd: [[String: Any]] = []
        if addParent && modeID != bundleID {
            entriesToAdd.append(parentPreferenceEntry(bundleID: bundleID) as [String: Any])
            added += 1
        }
        entriesToAdd.append(activeEntry as [String: Any])
        added += 1

        switch activePlacement {
        case .prepend:
            repaired = entriesToAdd + retained
        case .append:
            repaired = retained + entriesToAdd
        case .afterFirstRetained:
            if let first = retained.first {
                repaired = [first] + entriesToAdd + retained.dropFirst()
            } else {
                repaired = entriesToAdd
            }
        }
    }

    return (
        entries: repaired,
        removed: removed,
        added: added,
        changed: !plistEntriesAreEqual(entries, repaired)
    )
}

private func writeUserPreferenceDictionary(_ dictionary: [String: Any], domain: String) throws {
    let url = userPreferencePlistURL(domain: domain)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    try data.write(to: url, options: .atomic)
}

private func repairPreferenceArray(
    domain: String,
    key: String,
    bundleID: String,
    modeID: String,
    legacyModeIDs: [String],
    removeParent: Bool,
    addParent: Bool,
    activePlacement: ActivePreferencePlacement = .append,
    addActive: Bool
) -> PreferenceRepairResult {
    var dictionary = directUserPreferenceDictionary(domain: domain)
    let current = dictionary[key] as? [[String: Any]] ?? []
    let repair = repairPreferenceEntries(
        current,
        bundleID: bundleID,
        modeID: modeID,
        legacyModeIDs: legacyModeIDs,
        removeParent: removeParent,
        addParent: addParent,
        activePlacement: activePlacement,
        addActive: addActive
    )

    if repair.changed {
        dictionary[key] = repair.entries
        do {
            try writeUserPreferenceDictionary(dictionary, domain: domain)
            CFPreferencesAppSynchronize(domain as CFString)
        } catch {
            fputs("Failed to repair \(domain) \(key): \(error)\n", stderr)
            exit(ExitCode.failure.rawValue)
        }
    }

    return PreferenceRepairResult(
        domain: domain,
        key: key,
        removed: repair.removed,
        added: repair.added,
        changed: repair.changed
    )
}

private func repairPreferences(
    bundleID: String,
    modeID: String,
    legacyModeIDs: [String],
    includeHistory: Bool,
    includeSelected: Bool,
    addActive: Bool,
    removeParentAnchor: Bool,
    addLegacyParentAnchor: Bool
) {
    let addParentAnchor = addActive && modeID != bundleID
    let removeEnabledParentAnchor = removeParentAnchor && !addActive
    var results = [
        repairPreferenceArray(
            domain: "com.apple.HIToolbox",
            key: "AppleEnabledInputSources",
            bundleID: bundleID,
            modeID: modeID,
            legacyModeIDs: legacyModeIDs,
            removeParent: removeEnabledParentAnchor,
            addParent: addParentAnchor,
            addActive: addActive
        ),
        repairPreferenceArray(
            domain: "com.apple.inputsources",
            key: "AppleEnabledThirdPartyInputSources",
            bundleID: bundleID,
            modeID: modeID,
            legacyModeIDs: legacyModeIDs,
            removeParent: removeEnabledParentAnchor,
            addParent: addParentAnchor,
            addActive: addActive
        )
    ]

    if includeHistory {
        results.append(
            repairPreferenceArray(
                domain: "com.apple.HIToolbox",
                key: "AppleInputSourceHistory",
                bundleID: bundleID,
                modeID: modeID,
                legacyModeIDs: legacyModeIDs,
                removeParent: true,
                addParent: false,
                activePlacement: includeSelected ? .prepend : .afterFirstRetained,
                addActive: addActive
            )
        )
    }

    if includeSelected {
        results.append(
            repairPreferenceArray(
                domain: "com.apple.HIToolbox",
                key: "AppleSelectedInputSources",
                bundleID: bundleID,
                modeID: modeID,
                legacyModeIDs: legacyModeIDs,
                removeParent: true,
                addParent: false,
                activePlacement: .prepend,
                addActive: addActive
            )
        )
    }

    for result in results {
        let prefix = "preference.repair.\(result.domain).\(result.key)"
        print("\(prefix).changed=\(result.changed)")
        print("\(prefix).removed=\(result.removed)")
        print("\(prefix).added=\(result.added)")
    }
    print("preference.repair.active.inputsource.id=\(modeID)")
    print("preference.repair.active.mode.id=\(modeID)")
    print("preference.repair.include.history=\(includeHistory)")
    print("preference.repair.include.selected=\(includeSelected)")
    print("preference.repair.add.active=\(addActive)")
    print("preference.repair.add.parent.anchor=\(addParentAnchor)")
    print("preference.repair.remove.parent.anchor=\(removeEnabledParentAnchor)")
    print("preference.repair.add.legacy.parent.anchor=false")
    print("preference.repair.legacy.parent.anchor.option=\(addLegacyParentAnchor)")
    TISSupport.postNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)
    if includeSelected {
        TISSupport.postNotification(kTISNotifySelectedKeyboardInputSourceChanged)
    }
}

private func printStatus(parentID: String, modeID: String, legacyModeIDs: [String]) {
    let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    let currentID = TISSupport.stringProperty(current, kTISPropertyInputSourceID) ?? ""
    let usesSingleInputSource = modeID == parentID
    let rawParentSources = TISSupport.inputSources(id: parentID)
    let rawModeSources = usesSingleInputSource ? rawParentSources : TISSupport.inputSources(id: modeID)
    let parentSources = TISSupport.deduplicatedDiagnosticSources(rawParentSources)
    let modeSources = usesSingleInputSource ? parentSources : TISSupport.deduplicatedDiagnosticSources(rawModeSources)
    let parent = parentSources.first
    let mode = modeSources.first
    let activeModeCount = modeSources.count
    let legacySourcesByID = legacyModeIDs.map { ($0, TISSupport.deduplicatedDiagnosticSources(TISSupport.inputSources(id: $0))) }
    let userVisibleModeCount = TISSupport.visibleUserModeCount(
        sources: parentSources + modeSources + legacySourcesByID.flatMap(\.1)
    )
    let legacyCounts = legacySourcesByID.map { ($0, $1.count) }
    let legacyTotal = legacyCounts.reduce(0) { $0 + $1.1 }

    print("current.id=\(currentID)")
    print("inputSource.found=\(mode != nil)")
    print("inputSource.enabled=\(TISSupport.boolProperty(mode, kTISPropertyInputSourceIsEnabled))")
    print("inputSource.selectCapable=\(TISSupport.boolProperty(mode, kTISPropertyInputSourceIsSelectCapable))")
    print("inputSource.selected=\(currentID == modeID)")
    print("inputSource.type=\(TISSupport.stringProperty(mode, kTISPropertyInputSourceType) ?? "")")
    print("inputSource.name=\(TISSupport.stringProperty(mode, kTISPropertyLocalizedName) ?? "")")
    print("inputSource.id=\(modeID)")
    print("inputSource.raw.count=\(rawModeSources.count)")
    print("inputSource.count=\(activeModeCount)")
    print("inputSource.singleSource=\(usesSingleInputSource)")
    print("parent.found=\(parent != nil)")
    print("parent.enabled=\(TISSupport.boolProperty(parent, kTISPropertyInputSourceIsEnabled))")
    print("parent.selectCapable=\(TISSupport.boolProperty(parent, kTISPropertyInputSourceIsSelectCapable))")
    print("parent.type=\(TISSupport.stringProperty(parent, kTISPropertyInputSourceType) ?? "")")
    print("parent.name=\(TISSupport.stringProperty(parent, kTISPropertyLocalizedName) ?? "")")
    print("mode.found=\(mode != nil)")
    print("mode.enabled=\(TISSupport.boolProperty(mode, kTISPropertyInputSourceIsEnabled))")
    print("mode.selectCapable=\(TISSupport.boolProperty(mode, kTISPropertyInputSourceIsSelectCapable))")
    print("mode.type=\(TISSupport.stringProperty(mode, kTISPropertyInputSourceType) ?? "")")
    print("mode.selected=\(currentID == modeID)")
    print("mode.name=\(TISSupport.stringProperty(mode, kTISPropertyLocalizedName) ?? "")")
    print("mode.count=\(activeModeCount)")
    print("user.visible.mode.count=\(userVisibleModeCount)")
    print("active.mode.id=\(modeID)")
    print("active.mode.raw.count=\(rawModeSources.count)")
    print("active.mode.count=\(activeModeCount)")
    print("legacy.mode.count=\(legacyTotal)")
    for (index, legacy) in legacyCounts.enumerated() {
        print("legacy.mode.\(index).id=\(legacy.0)")
        print("legacy.mode.\(index).count=\(legacy.1)")
    }
    print("preference.selected.mode=\(hitoolboxSelectedModeID() ?? "")")
    print("preference.selected.knowtype=\(preferencesContainInputMode(bundleID: parentID, modeID: modeID, domain: "com.apple.HIToolbox", key: "AppleSelectedInputSources"))")
    print("preference.selected.parent.knowtype=\(modeID != parentID && preferencesContainEntry(preferenceArray("AppleSelectedInputSources", domain: "com.apple.HIToolbox"), target: parentPreferenceEntry(bundleID: parentID)))")
    print("preference.enabled.knowtype=\(preferencesContainInputMode(bundleID: parentID, modeID: modeID, domain: "com.apple.HIToolbox", key: "AppleEnabledInputSources"))")
    print("preference.enabled.parent.knowtype=\(modeID != parentID && preferencesContainEntry(preferenceArray("AppleEnabledInputSources", domain: "com.apple.HIToolbox"), target: parentPreferenceEntry(bundleID: parentID)))")
    print("preference.enabled.legacy.knowtype=\(preferencesContainAnyInputMode(bundleID: parentID, modeIDs: legacyModeIDs, domain: "com.apple.HIToolbox", key: "AppleEnabledInputSources"))")
    print("preference.thirdparty.enabled.knowtype=\(preferencesContainInputMode(bundleID: parentID, modeID: modeID, domain: "com.apple.inputsources", key: "AppleEnabledThirdPartyInputSources"))")
    print("preference.thirdparty.enabled.parent.knowtype=\(modeID != parentID && preferencesContainEntry(preferenceArray("AppleEnabledThirdPartyInputSources", domain: "com.apple.inputsources"), target: parentPreferenceEntry(bundleID: parentID)))")
    print("preference.thirdparty.enabled.legacy.knowtype=\(preferencesContainAnyInputMode(bundleID: parentID, modeIDs: legacyModeIDs, domain: "com.apple.inputsources", key: "AppleEnabledThirdPartyInputSources"))")
    print("preference.history.knowtype=\(preferencesContainInputMode(bundleID: parentID, modeID: modeID, domain: "com.apple.HIToolbox", key: "AppleInputSourceHistory"))")
    print("preference.history.parent.knowtype=\(modeID != parentID && preferencesContainEntry(preferenceArray("AppleInputSourceHistory", domain: "com.apple.HIToolbox"), target: parentPreferenceEntry(bundleID: parentID)))")
    let historyEntries = preferenceArray("AppleInputSourceHistory", domain: "com.apple.HIToolbox")
    let activeEntry = activePreferenceEntry(bundleID: parentID, modeID: modeID)
    let historyIndex = historyEntries.firstIndex { preferenceEntryMatches($0, target: activeEntry) }
    print("preference.history.index.knowtype=\(historyIndex.map(String.init) ?? "-1")")
}

private func printDump(bundleID: String) {
    let rawSources = TISSupport.inputSources(bundleID: bundleID)
    let sources = TISSupport.deduplicatedDiagnosticSources(rawSources)
    print("bundle.id=\(bundleID)")
    print("bundle.raw.count=\(rawSources.count)")
    print("bundle.count=\(sources.count)")

    for (index, source) in sources.enumerated() {
        let id = TISSupport.stringProperty(source, kTISPropertyInputSourceID) ?? ""
        let modeID = TISSupport.stringProperty(source, kTISPropertyInputModeID) ?? ""
        let name = TISSupport.stringProperty(source, kTISPropertyLocalizedName) ?? ""
        let category = TISSupport.stringProperty(source, kTISPropertyInputSourceCategory) ?? ""
        let type = TISSupport.stringProperty(source, kTISPropertyInputSourceType) ?? ""

        print("source.\(index).id=\(id)")
        print("source.\(index).mode=\(modeID)")
        print("source.\(index).name=\(name)")
        print("source.\(index).category=\(category)")
        print("source.\(index).type=\(type)")
        print("source.\(index).enabled=\(TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnabled))")
        print("source.\(index).enableCapable=\(TISSupport.boolProperty(source, kTISPropertyInputSourceIsEnableCapable))")
        print("source.\(index).selectCapable=\(TISSupport.boolProperty(source, kTISPropertyInputSourceIsSelectCapable))")
        print("source.\(index).asciiCapable=\(TISSupport.boolProperty(source, kTISPropertyInputSourceIsASCIICapable))")
    }
}

private func repairSelectedPreferenceAwayFromKnowType(
    bundleID: String,
    modeID: String,
    legacyModeIDs: [String]
) -> PreferenceRepairResult {
    let domain = "com.apple.HIToolbox"
    let key = "AppleSelectedInputSources"
    var dictionary = directUserPreferenceDictionary(domain: domain)
    let current = dictionary[key] as? [[String: Any]] ?? []
    let modeIDs = Set([modeID] + legacyModeIDs)
    var removed = 0
    let repaired = current.filter { entry in
        let shouldRemove = isKnowTypePreferenceEntry(entry, bundleID: bundleID, modeIDs: modeIDs)
        if shouldRemove {
            removed += 1
        }
        return !shouldRemove
    }

    let changed = !plistEntriesAreEqual(current, repaired)
    if changed {
        dictionary[key] = repaired
        do {
            try writeUserPreferenceDictionary(dictionary, domain: domain)
            CFPreferencesAppSynchronize(domain as CFString)
        } catch {
            fputs("Failed to repair \(domain) \(key): \(error)\n", stderr)
            exit(ExitCode.failure.rawValue)
        }
    }

    return PreferenceRepairResult(
        domain: domain,
        key: key,
        removed: removed,
        added: 0,
        changed: changed
    )
}

private func switchAway(
    prefix: String,
    fallbackID: String,
    bundleID: String,
    modeID: String,
    legacyModeIDs: [String]
) {
    let beforeID = TISSupport.currentInputSourceID() ?? ""
    var selectStatus: OSStatus?
    if beforeID.hasPrefix(prefix), let fallback = TISSupport.inputSource(id: fallbackID) {
        selectStatus = TISSelectInputSource(fallback)
    }
    let repair = repairSelectedPreferenceAwayFromKnowType(
        bundleID: bundleID,
        modeID: modeID,
        legacyModeIDs: legacyModeIDs
    )
    if selectStatus == noErr || repair.changed {
        TISSupport.postNotification(kTISNotifySelectedKeyboardInputSourceChanged)
    }
    print("switch-away.current.before=\(beforeID)")
    if let selectStatus {
        print("switch-away.select.status=\(selectStatus)")
    } else {
        print("switch-away.select.status=skipped")
    }
    print("switch-away.preference.selected.changed=\(repair.changed)")
    print("switch-away.preference.selected.removed=\(repair.removed)")
    print("switch-away.current.after=\(TISSupport.currentInputSourceID() ?? "")")
}

private func bootstrap(
    path: String,
    parentID: String,
    modeID: String,
    legacyModeIDs: [String],
    select: Bool,
    requireSelected: Bool = false
) {
    let registrationStatus = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
    if registrationStatus != noErr {
        fputs("Warning: TISRegisterInputSource returned \(registrationStatus)\n", stderr)
    }

    guard TISSupport.waitForInputSource(id: parentID, timeout: 5.0) != nil,
          let parent = TISSupport.bestActivationTarget(TISSupport.inputSources(id: parentID)) else {
        fputs("KnowType input source was not found after bootstrap.\n", stderr)
        exit(ExitCode.failure.rawValue)
    }
    guard TISSupport.waitForInputSource(id: modeID, timeout: 5.0) != nil,
          let mode = select
            ? TISSupport.bestSelectionTarget(TISSupport.inputSources(id: modeID))
            : TISSupport.bestActivationTarget(TISSupport.inputSources(id: modeID)) else {
        fputs("KnowType active input source was not found after bootstrap.\n", stderr)
        exit(ExitCode.failure.rawValue)
    }

    let parentEnabled = enableInputSource(parent, label: "parent")
    let modeEnabled = enableInputSource(mode, label: "mode")

    TISSupport.postNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)

    var selectStatus = noErr
    if select {
        selectStatus = selectMode(
            parentID: parentID,
            modeID: modeID,
            requireSelected: requireSelected,
            exitOnFailure: false
        )
    }

    print("bootstrap.path=\(path)")
    print("bootstrap.register.status=\(registrationStatus)")
    print("bootstrap.preference.writes=skipped")
    print("bootstrap.singleSource=\(modeID == parentID)")
    print("bootstrap.parent.enabled=\(parentEnabled)")
    print("bootstrap.mode.enabled=\(modeEnabled)")
    print("bootstrap.selected=\(select)")
    if !parentEnabled || !modeEnabled {
        exit(ExitCode.failure.rawValue)
    }
    if selectStatus != noErr {
        exit(ExitCode.failure.rawValue)
    }
}

private func disableLegacyModes(_ legacyModeIDs: [String]) -> Int {
    var disabled = 0
    for modeID in legacyModeIDs {
        for source in TISSupport.deduplicatedDiagnosticSources(TISSupport.inputSources(id: modeID)) {
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

private func purgeLegacy(path: String, parentID: String, modeID: String, legacyModeIDs: [String]) {
    let disabled = disableLegacyModes(legacyModeIDs)
    let unregistered = LSSupport.unregisterStaleLaunchServices(
        path: path,
        bundleID: parentID,
        warning: { fputs($0 + "\n", stderr) }
    )
    print("purge.legacy.disabled=\(disabled)")
    print("purge.legacy.preference.writes=skipped")
    print("purge.active.inputsource.id=\(modeID)")
    print("purge.active.mode.id=\(modeID)")
    print("purge.launchservices.unregistered=\(unregistered)")
    print("purge.launchservices.registered=false")
}

private func register(path: String, parentID: String, modeID: String, select: Bool) {
    bootstrap(path: path, parentID: parentID, modeID: modeID, legacyModeIDs: defaultLegacyModeIDs, select: select)
}

@discardableResult
private func selectMode(parentID: String, modeID: String, requireSelected: Bool, exitOnFailure: Bool = true) -> OSStatus {
    guard let parent = TISSupport.bestActivationTarget(TISSupport.inputSources(id: parentID)) else {
        fputs("KnowType input source was not found. Run ./scripts/install-inputmethod.sh first.\n", stderr)
        if exitOnFailure {
            exit(ExitCode.failure.rawValue)
        }
        return OSStatus(paramErr)
    }
    guard let mode = TISSupport.bestSelectionTarget(TISSupport.inputSources(id: modeID)) else {
        fputs("KnowType active input source was not found. Run ./scripts/install-inputmethod.sh first.\n", stderr)
        if exitOnFailure {
            exit(ExitCode.failure.rawValue)
        }
        return OSStatus(paramErr)
    }

    enableInputSource(parent, label: "parent")
    enableInputSource(mode, label: "mode")
    TISSupport.postNotification(kTISNotifyEnabledKeyboardInputSourcesChanged)

    let selectStatus = TISSelectInputSource(mode)
    if selectStatus == noErr {
        print("Requested KnowType input source selection: \(modeID)")
        print("preference.writes=skipped")
        TISSupport.postNotification(kTISNotifySelectedKeyboardInputSourceChanged)
    } else {
        fputs("TISSelectInputSource returned \(selectStatus). Enable or select KnowType from System Settings if macOS did not switch automatically.\n", stderr)
        print("select.status=\(selectStatus)")
        if exitOnFailure {
            exit(Int32(selectStatus))
        }
        return selectStatus
    }

    let deadline = Date().addingTimeInterval(2.0)
    var currentID = TISSupport.currentInputSourceID()
    while currentID != modeID && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
        currentID = TISSupport.currentInputSourceID()
    }
    print("select.current=\(currentID ?? "")")

    if currentID == modeID {
        print("Verified KnowType only in this helper-local TIS context: \(modeID)")
        print("The macOS menu bar or another app may still use a different input source.")
        print("Select KnowType in the target text app, then type a real probe before accepting manual typing.")
    } else {
        let observed = currentID ?? "<unavailable>"
        fputs("Warning: this preflight TIS context is \(observed), not \(modeID). Activate the target text app, rerun this helper, then type a real probe in that app.\n", stderr)
        if requireSelected {
            if exitOnFailure {
                exit(ExitCode.failure.rawValue)
            }
            return OSStatus(paramErr)
        }
    }

    return selectStatus
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
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    arguments.ensureConsumed()
    printStatus(parentID: parentID, modeID: modeID, legacyModeIDs: legacyModeIDs)
case "dump":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    arguments.ensureConsumed()
    printDump(bundleID: bundleID)
case "disable":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    arguments.ensureConsumed()
    disableInputSources(bundleID: bundleID)
case "inspect-preferences", "dedupe-preferences":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    arguments.ensureConsumed()
    inspectPreferences(bundleID: bundleID, modeIDs: Set([modeID] + legacyModeIDs))
case "repair-preferences":
    let bundleID = arguments.option("--bundle-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    let includeHistory = arguments.flag("--include-history")
    let includeSelected = arguments.flag("--include-selected")
    let addActive = arguments.flag("--add-active")
    let removeParentAnchor = arguments.flag("--remove-parent-anchor")
    let addLegacyParentAnchor = arguments.flag("--legacy-parent-anchor")
    arguments.ensureConsumed()
    repairPreferences(
        bundleID: bundleID,
        modeID: modeID,
        legacyModeIDs: legacyModeIDs,
        includeHistory: includeHistory,
        includeSelected: includeSelected,
        addActive: addActive,
        removeParentAnchor: removeParentAnchor,
        addLegacyParentAnchor: addLegacyParentAnchor
    )
case "switch-away":
    let prefix = arguments.option("--prefix", default: defaultParentID) ?? defaultParentID
    let fallbackID = arguments.option("--fallback-id", default: defaultFallbackID) ?? defaultFallbackID
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    arguments.ensureConsumed()
    switchAway(
        prefix: prefix,
        fallbackID: fallbackID,
        bundleID: parentID,
        modeID: modeID,
        legacyModeIDs: legacyModeIDs
    )
case "register":
    guard let path = arguments.option("--path") else {
        usage()
    }
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let select = arguments.flag("--select")
    arguments.ensureConsumed()
    register(path: path, parentID: parentID, modeID: modeID, select: select)
case "bootstrap":
    guard let path = arguments.option("--path") else {
        usage()
    }
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    let select = arguments.flag("--select")
    let requireSelected = arguments.flag("--require-selected")
    arguments.ensureConsumed()
    bootstrap(
        path: path,
        parentID: parentID,
        modeID: modeID,
        legacyModeIDs: legacyModeIDs,
        select: select,
        requireSelected: requireSelected
    )
case "purge-legacy":
    guard let path = arguments.option("--path") else {
        usage()
    }
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let legacyModeIDs = legacyModeIDs(from: &arguments)
    arguments.ensureConsumed()
    purgeLegacy(path: path, parentID: parentID, modeID: modeID, legacyModeIDs: legacyModeIDs)
case "select":
    let parentID = arguments.option("--parent-id", default: defaultParentID) ?? defaultParentID
    let modeID = arguments.option("--mode-id", default: defaultModeID) ?? defaultModeID
    let requireSelected = arguments.flag("--require-selected")
    arguments.ensureConsumed()
    selectMode(parentID: parentID, modeID: modeID, requireSelected: requireSelected)
case "migrate-provider-profiles":
    arguments.ensureConsumed()
    exit(ProviderProfileStorageCommand.migrate())
case "downgrade-provider-profiles":
    arguments.ensureConsumed()
    exit(ProviderProfileStorageCommand.downgradeForLegacyRuntime())
case "rollback-provider-profile-migration":
    guard let rawRevision = arguments.option("--expected-revision"),
          let revision = UInt64(rawRevision) else {
        usage()
    }
    arguments.ensureConsumed()
    exit(ProviderProfileStorageCommand.rollback(expectedCanonicalRevision: revision))
default:
    usage()
}
