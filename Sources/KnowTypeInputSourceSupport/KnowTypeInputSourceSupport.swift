import Carbon
import Foundation

public struct KnowTypeProcessResult: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public enum KnowTypeLaunchServicesSupport {
    public static let defaultLSRegisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static func runProcess(_ executable: String, _ arguments: [String]) -> KnowTypeProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return KnowTypeProcessResult(status: 1, output: "")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return KnowTypeProcessResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    public static func stripLSRegisterSuffix(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+\(0x[0-9A-Fa-f]+\)$"#,
            with: "",
            options: .regularExpression
        )
    }

    public static func expandedPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory + "/" + path.dropFirst(2)
        }
        return path
    }

    public static func canonicalBundlePath(
        _ path: String,
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        let expanded = expandedPath(stripLSRegisterSuffix(path), homeDirectory: homeDirectory)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        }
        return expanded
    }

    public static func parseLaunchServicesPaths(bundleID: String, dump: String) -> [String] {
        var paths: [String] = []
        var currentPath = ""
        for rawLine in dump.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
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

    public static func launchServicesPaths(
        bundleID: String,
        lsregisterPath: String = defaultLSRegisterPath,
        fileManager: FileManager = .default,
        runner: (String, [String]) -> KnowTypeProcessResult = runProcess
    ) -> [String] {
        guard fileManager.isExecutableFile(atPath: lsregisterPath) else {
            return []
        }
        let result = runner(lsregisterPath, ["-dump"])
        guard result.status == 0 else {
            return []
        }
        return parseLaunchServicesPaths(bundleID: bundleID, dump: result.output)
    }

    public static func unregisterStaleLaunchServices(
        path: String,
        bundleID: String,
        lsregisterPath: String = defaultLSRegisterPath,
        fileManager: FileManager = .default,
        runner: (String, [String]) -> KnowTypeProcessResult = runProcess,
        warning: (String) -> Void = { _ in }
    ) -> Int {
        guard fileManager.isExecutableFile(atPath: lsregisterPath) else {
            warning("Warning: lsregister command is unavailable.")
            return 0
        }

        let canonicalTarget = canonicalBundlePath(path, fileManager: fileManager)
        var unregistered = 0
        for candidate in launchServicesPaths(
            bundleID: bundleID,
            lsregisterPath: lsregisterPath,
            fileManager: fileManager,
            runner: runner
        ) {
            let canonicalCandidate = canonicalBundlePath(candidate, fileManager: fileManager)
            guard canonicalCandidate != canonicalTarget else {
                continue
            }
            let unregisterPath = expandedPath(stripLSRegisterSuffix(candidate))
            let result = runner(lsregisterPath, ["-u", unregisterPath])
            if result.status == 0 {
                unregistered += 1
            } else if !fileManager.fileExists(atPath: unregisterPath) {
                _ = runner(lsregisterPath, ["-gc"])
            } else {
                warning("Warning: lsregister -u failed for \(unregisterPath)")
            }
        }
        return unregistered
    }
}

public struct KnowTypeInputSourceProperties: Equatable, Sendable {
    public var id: String?
    public var modeID: String?
    public var type: String?
    public var category: String?
    public var bundleID: String?
    public var localizedName: String?
    public var isEnabled: Bool
    public var isEnableCapable: Bool
    public var isSelectCapable: Bool

    public init(
        id: String? = nil,
        modeID: String? = nil,
        type: String? = nil,
        category: String? = nil,
        bundleID: String? = nil,
        localizedName: String? = nil,
        isEnabled: Bool = false,
        isEnableCapable: Bool = false,
        isSelectCapable: Bool = false
    ) {
        self.id = id
        self.modeID = modeID
        self.type = type
        self.category = category
        self.bundleID = bundleID
        self.localizedName = localizedName
        self.isEnabled = isEnabled
        self.isEnableCapable = isEnableCapable
        self.isSelectCapable = isSelectCapable
    }
}

public enum KnowTypeTISSupport {
    public static func stringProperty(_ source: TISInputSource?, _ key: CFString) -> String? {
        guard let source, let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    public static func boolProperty(_ source: TISInputSource?, _ key: CFString) -> Bool {
        guard let source, let raw = TISGetInputSourceProperty(source, key) else {
            return false
        }
        return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
    }

    public static func inputModeID(_ source: TISInputSource?) -> String? {
        stringProperty(source, kTISPropertyInputModeID)
    }

    public static func properties(for source: TISInputSource?) -> KnowTypeInputSourceProperties {
        KnowTypeInputSourceProperties(
            id: stringProperty(source, kTISPropertyInputSourceID),
            modeID: stringProperty(source, kTISPropertyInputModeID),
            type: stringProperty(source, kTISPropertyInputSourceType),
            category: stringProperty(source, kTISPropertyInputSourceCategory),
            bundleID: stringProperty(source, kTISPropertyBundleID),
            localizedName: stringProperty(source, kTISPropertyLocalizedName),
            isEnabled: boolProperty(source, kTISPropertyInputSourceIsEnabled),
            isEnableCapable: boolProperty(source, kTISPropertyInputSourceIsEnableCapable),
            isSelectCapable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        )
    }

    public static func inputSources(id: String) -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    public static func inputSources(bundleID: String) -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    public static func inputSource(id: String) -> TISInputSource? {
        inputSources(id: id).first
    }

    public static func currentInputSourceID() -> String? {
        stringProperty(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), kTISPropertyInputSourceID)
    }

    public static func postNotification(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    public static func diagnosticSignature(for properties: KnowTypeInputSourceProperties) -> String {
        [
            properties.id ?? "",
            properties.modeID ?? "",
            properties.type ?? "",
            properties.category ?? "",
            properties.bundleID ?? "",
            properties.localizedName ?? ""
        ].joined(separator: "|")
    }

    public static func activationSignature(for properties: KnowTypeInputSourceProperties) -> String {
        [
            properties.id ?? "",
            properties.modeID ?? "",
            properties.type ?? ""
        ].joined(separator: "|")
    }

    public static func diagnosticSourceSignature(_ source: TISInputSource) -> String {
        diagnosticSignature(for: properties(for: source))
    }

    public static func activationSourceSignature(_ source: TISInputSource) -> String {
        activationSignature(for: properties(for: source))
    }

    public static func sourceIsBetterActivationTarget(
        _ candidate: KnowTypeInputSourceProperties,
        than existing: KnowTypeInputSourceProperties
    ) -> Bool {
        if candidate.isEnableCapable != existing.isEnableCapable {
            return candidate.isEnableCapable
        }
        if candidate.isSelectCapable != existing.isSelectCapable {
            return candidate.isSelectCapable
        }
        if candidate.isEnabled != existing.isEnabled {
            return candidate.isEnabled
        }
        return false
    }

    public static func sourceIsBetterSelectionTarget(
        _ candidate: KnowTypeInputSourceProperties,
        than existing: KnowTypeInputSourceProperties
    ) -> Bool {
        if candidate.isSelectCapable != existing.isSelectCapable {
            return candidate.isSelectCapable
        }
        if candidate.isEnabled != existing.isEnabled {
            return candidate.isEnabled
        }
        if candidate.isEnableCapable != existing.isEnableCapable {
            return candidate.isEnableCapable
        }
        return false
    }

    public static func sourceIsBetterActivationTarget(_ candidate: TISInputSource, than existing: TISInputSource) -> Bool {
        sourceIsBetterActivationTarget(properties(for: candidate), than: properties(for: existing))
    }

    public static func sourceIsBetterSelectionTarget(_ candidate: TISInputSource, than existing: TISInputSource) -> Bool {
        sourceIsBetterSelectionTarget(properties(for: candidate), than: properties(for: existing))
    }

    public static func bestSelectionTarget(_ sources: [TISInputSource]) -> TISInputSource? {
        sources.reduce(nil) { best, source in
            guard let best else {
                return source
            }
            return sourceIsBetterSelectionTarget(source, than: best) ? source : best
        }
    }

    public static func bestActivationTarget(_ sources: [TISInputSource]) -> TISInputSource? {
        sources.reduce(nil) { best, source in
            guard let best else {
                return source
            }
            return sourceIsBetterActivationTarget(source, than: best) ? source : best
        }
    }

    public static func enableParentBeforeModes(
        _ lhs: KnowTypeInputSourceProperties,
        _ rhs: KnowTypeInputSourceProperties
    ) -> Bool {
        lhs.modeID == nil && rhs.modeID != nil
    }

    public static func disableModesBeforeParent(
        _ lhs: KnowTypeInputSourceProperties,
        _ rhs: KnowTypeInputSourceProperties
    ) -> Bool {
        lhs.modeID != nil && rhs.modeID == nil
    }

    public static func enableParentBeforeModes(_ lhs: TISInputSource, _ rhs: TISInputSource) -> Bool {
        enableParentBeforeModes(properties(for: lhs), properties(for: rhs))
    }

    public static func disableModesBeforeParent(_ lhs: TISInputSource, _ rhs: TISInputSource) -> Bool {
        disableModesBeforeParent(properties(for: lhs), properties(for: rhs))
    }

    public static func deduplicatedSources(
        _ sources: [TISInputSource],
        signature: (TISInputSource) -> String,
        prefers candidateIsBetter: ((TISInputSource, TISInputSource) -> Bool)? = nil
    ) -> [TISInputSource] {
        var orderedSignatures: [String] = []
        var sourcesBySignature: [String: TISInputSource] = [:]

        for source in sources {
            let sourceSignature = signature(source)
            guard let existing = sourcesBySignature[sourceSignature] else {
                orderedSignatures.append(sourceSignature)
                sourcesBySignature[sourceSignature] = source
                continue
            }
            if candidateIsBetter?(source, existing) == true {
                sourcesBySignature[sourceSignature] = source
            }
        }

        return orderedSignatures.compactMap { sourcesBySignature[$0] }
    }

    public static func deduplicatedDiagnosticSources(_ sources: [TISInputSource]) -> [TISInputSource] {
        deduplicatedSources(sources, signature: diagnosticSourceSignature)
    }

    public static func deduplicatedActivationSources(_ sources: [TISInputSource]) -> [TISInputSource] {
        deduplicatedSources(
            sources,
            signature: activationSourceSignature,
            prefers: sourceIsBetterActivationTarget
        )
    }

    public static func visibleUserModeCount(_ properties: [KnowTypeInputSourceProperties]) -> Int {
        var visibleIDs = Set<String>()
        for source in properties where source.isEnabled && source.isSelectCapable {
            if let id = source.id {
                visibleIDs.insert(id)
            }
        }
        return visibleIDs.count
    }

    public static func visibleUserModeCount(sources: [TISInputSource]) -> Int {
        visibleUserModeCount(sources.map(properties))
    }

    public static func waitForInputSource(
        id: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.25
    ) -> TISInputSource? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let source = inputSource(id: id) {
                return source
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return inputSource(id: id)
    }

    public static func waitForCurrentInputSourceID(
        _ id: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var currentID = currentInputSourceID()
        while currentID != id && Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            currentID = currentInputSourceID()
        }
        return currentID
    }
}
