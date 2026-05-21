import Foundation

enum SettingsLocalization {
    static let tableName = "Localizable"

    static func string(_ key: String) -> String {
        string(key, localeIdentifier: "zh-Hans")
    }

    static func string(_ key: String, localeIdentifier: String) -> String {
        guard let localizedBundle = localizedBundle(localeIdentifier: localeIdentifier) else {
            return Bundle.module.localizedString(forKey: key, value: key, table: tableName)
        }

        return localizedBundle.localizedString(forKey: key, value: key, table: tableName)
    }

    private static func localizedBundle(localeIdentifier: String) -> Bundle? {
        let candidates = [
            localeIdentifier,
            localeIdentifier.lowercased(),
            localeIdentifier.replacingOccurrences(of: "_", with: "-"),
            localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        ]

        for candidate in candidates {
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
}
