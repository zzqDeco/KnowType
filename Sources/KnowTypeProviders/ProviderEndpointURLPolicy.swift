import Foundation

public enum ProviderEndpointURLPolicy {
    public static func validatedHTTPURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }

    public static func isAllowedRuntimeURL(_ url: URL) -> Bool {
        validatedHTTPURL(url.absoluteString) != nil
    }

    public static func privacySafeSummary(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid endpoint>"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<invalid endpoint>"
    }
}
