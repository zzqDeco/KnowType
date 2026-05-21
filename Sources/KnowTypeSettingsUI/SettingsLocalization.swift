import Foundation

public enum SettingsLocalization {
    public static let tableName = "Localizable"

    public static func string(_ key: String) -> String {
        string(key, preferredLanguages: Locale.preferredLanguages)
    }

    static func string(_ key: String, preferredLanguages: [String]) -> String {
        for localeIdentifier in preferredLanguages {
            if let localizedBundle = localizedBundle(localeIdentifier: localeIdentifier) {
                return localizedBundle.localizedString(forKey: key, value: key, table: tableName)
            }
        }

        let fallback = preferredLanguages.contains { languageCode(from: $0) == "zh" } ? "zh-Hans" : "en"
        return string(key, localeIdentifier: fallback)
    }

    public static func string(_ key: String, localeIdentifier: String) -> String {
        let fallbackIdentifiers = [
            localeIdentifier,
            languageCode(from: localeIdentifier) == "zh" ? "zh-Hans" : "en",
            "en",
            "zh-Hans"
        ]

        for fallbackIdentifier in unique(fallbackIdentifiers) {
            if let localizedBundle = localizedBundle(localeIdentifier: fallbackIdentifier) {
                return localizedBundle.localizedString(forKey: key, value: key, table: tableName)
            }
        }

        return key
    }

    private static func localizedBundle(localeIdentifier: String) -> Bundle? {
        for candidate in localeCandidates(for: localeIdentifier) {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        let available = Bundle.module.localizations.first {
            $0.caseInsensitiveCompare(localeIdentifier) == .orderedSame
        }
        return available
            .flatMap { Bundle.module.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:))
    }

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
}
