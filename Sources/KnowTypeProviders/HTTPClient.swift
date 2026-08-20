import Foundation
import KnowTypeCore

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("missing HTTPURLResponse")
        }
        return (data, httpResponse)
    }
}

func applyCommonHeaders(_ request: inout URLRequest, configuration: ProviderConfiguration) {
    request.timeoutInterval = configuration.timeoutSeconds
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in configuration.headers {
        request.setValue(value, forHTTPHeaderField: key)
    }
}

func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
    guard (200..<300).contains(response.statusCode) else {
        if response.statusCode == 429 {
            throw ProviderRateLimitError(
                retryAfterSeconds: retryAfterSeconds(from: response.value(forHTTPHeaderField: "Retry-After")),
                bodyByteCount: data.count
            )
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw ProviderError.httpStatus(response.statusCode, body)
    }
}

func jsonData(_ object: Any, task: LLMTask? = nil) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    if let task { try ProviderRequestBudget.validateHTTPBody(data, task: task) }
    return data
}

func retryAfterSeconds(from value: String?, now: Date = Date()) -> TimeInterval? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    if let seconds = TimeInterval(value) {
        return ProviderRateLimitError.normalizedRetryAfterSeconds(seconds)
    }
    guard let date = HTTPDateFormatter.date(from: value) else { return nil }
    let delay = date.timeIntervalSince(now)
    guard delay.isFinite else { return nil }
    return ProviderRateLimitError.normalizedRetryAfterSeconds(max(0, delay))
}

private enum HTTPDateFormatter {
    private static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss z",
        "EEEE, dd-MMM-yy HH:mm:ss z",
        "EEE MMM d HH:mm:ss yyyy"
    ]

    static func date(from value: String) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
