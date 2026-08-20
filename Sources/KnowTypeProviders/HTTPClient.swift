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

private func retryAfterSeconds(from value: String?) -> TimeInterval? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    if let seconds = TimeInterval(value) { return seconds }
    guard let date = HTTPDateFormatter.shared.date(from: value) else { return nil }
    return date.timeIntervalSinceNow
}

private enum HTTPDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter
    }()
}
