import Foundation

public enum SettingsLocalization {
    public static let tableName = "Localizable"
    private static let resourceBundleName = "KnowType_KnowTypeSettingsUI.bundle"
    private static let cachedResourceBundle = locateSettingsResourceBundle()

    private final class BundleToken: NSObject {}

    public static func string(_ key: String) -> String {
        string(key, preferredLanguages: Locale.preferredLanguages)
    }

    static func string(_ key: String, preferredLanguages: [String]) -> String {
        string(key, preferredLanguages: preferredLanguages, bundleResolver: localizedBundle(localeIdentifier:))
    }

    static func string(
        _ key: String,
        preferredLanguages: [String],
        bundleResolver: (String) -> Bundle?
    ) -> String {
        for localeIdentifier in preferredLanguages {
            if let value = localizedValue(
                forKey: key,
                localeIdentifier: localeIdentifier,
                bundleResolver: bundleResolver
            ) {
                return value
            }
        }

        let fallback = preferredLanguages.contains { languageCode(from: $0) == "zh" } ? "zh-Hans" : "en"
        return string(key, localeIdentifier: fallback, bundleResolver: bundleResolver)
    }

    public static func string(_ key: String, localeIdentifier: String) -> String {
        string(key, localeIdentifier: localeIdentifier, bundleResolver: localizedBundle(localeIdentifier:))
    }

    static func string(
        _ key: String,
        localeIdentifier: String,
        bundleResolver: (String) -> Bundle?
    ) -> String {
        let fallbackIdentifiers = [
            localeIdentifier,
            languageCode(from: localeIdentifier) == "zh" ? "zh-Hans" : "en",
            "en",
            "zh-Hans"
        ]

        for fallbackIdentifier in unique(fallbackIdentifiers) {
            if let value = localizedValue(
                forKey: key,
                localeIdentifier: fallbackIdentifier,
                bundleResolver: bundleResolver
            ) {
                return value
            }
        }

        return key
    }

    private static func localizedValue(
        forKey key: String,
        localeIdentifier: String,
        bundleResolver: (String) -> Bundle?
    ) -> String? {
        guard let localizedBundle = bundleResolver(localeIdentifier) else {
            return nil
        }
        let value = localizedBundle.localizedString(forKey: key, value: key, table: tableName)
        return value == key ? nil : value
    }

    private static func localizedBundle(localeIdentifier: String) -> Bundle? {
        guard let resourceBundle = settingsResourceBundle() else {
            return nil
        }

        for candidate in localeCandidates(for: localeIdentifier) {
            if let path = resourceBundle.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        let available = resourceBundle.localizations.first {
            $0.caseInsensitiveCompare(localeIdentifier) == .orderedSame
        }
        return available
            .flatMap { resourceBundle.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:))
    }

    private static func settingsResourceBundle() -> Bundle? {
        cachedResourceBundle
    }

    private static func locateSettingsResourceBundle() -> Bundle? {
        for candidate in resourceBundleCandidates() {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

    private static func resourceBundleCandidates() -> [URL] {
        var candidates: [URL] = []
        let markerBundle = Bundle(for: BundleToken.self)

        appendResourceBundleCandidates(from: Bundle.main, to: &candidates)
        appendResourceBundleCandidates(from: markerBundle, to: &candidates)
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            appendResourceBundleCandidates(from: bundle, to: &candidates)
        }

        #if SWIFT_PACKAGE
        if isSwiftPMBuildOrTestProcess {
            candidates.append(contentsOf: swiftPMBuildResourceBundleCandidates())
        }
        #endif

        return uniqueURLs(candidates)
    }

    private static func appendResourceBundleCandidates(from bundle: Bundle, to candidates: inout [URL]) {
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(resourceBundleName))
        }
        for baseURL in ancestorURLs(from: bundle.bundleURL, limit: 6) {
            candidates.append(baseURL.appendingPathComponent("Contents/Resources/\(resourceBundleName)"))
            candidates.append(baseURL.appendingPathComponent(resourceBundleName))
        }
    }

    private static func ancestorURLs(from url: URL, limit: Int) -> [URL] {
        var urls: [URL] = []
        var current = url
        for _ in 0..<max(1, limit) {
            urls.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else {
                break
            }
            current = parent
        }
        return urls
    }

    #if SWIFT_PACKAGE
    private static var isSwiftPMBuildOrTestProcess: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return CommandLine.arguments.contains { argument in
            argument.contains(".build") || argument.contains(".xctest")
        }
    }

    private static func swiftPMBuildResourceBundleCandidates() -> [URL] {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildURL = rootURL.appendingPathComponent(".build")
        var candidates = [
            buildURL.appendingPathComponent("debug/\(resourceBundleName)"),
            buildURL.appendingPathComponent("release/\(resourceBundleName)")
        ]

        let fileManager = FileManager.default
        let platformBuildURLs = (try? fileManager.contentsOfDirectory(
            at: buildURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for platformBuildURL in platformBuildURLs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: platformBuildURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            candidates.append(platformBuildURL.appendingPathComponent("debug/\(resourceBundleName)"))
            candidates.append(platformBuildURL.appendingPathComponent("release/\(resourceBundleName)"))
        }

        return candidates
    }
    #endif

    private static func localeCandidates(for localeIdentifier: String) -> [String] {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        let language = parts.first?.lowercased()
        var candidates = [
            localeIdentifier,
            normalized,
            normalized.lowercased()
        ]

        if parts.count >= 2 {
            candidates.append(parts.prefix(2).joined(separator: "-"))
        }
        if let language {
            candidates.append(language)
            if language == "zh" {
                candidates.append("zh-Hans")
            }
        }
        return unique(candidates)
    }

    private static func languageCode(from localeIdentifier: String) -> String {
        localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map { String($0).lowercased() } ?? localeIdentifier.lowercased()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    private static func uniqueURLs(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.filter { value in
            seen.insert(value.standardizedFileURL.path).inserted
        }
    }
}
