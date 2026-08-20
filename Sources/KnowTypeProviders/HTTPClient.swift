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
        return normalizedRetryAfterHeaderSeconds(seconds)
    }
    guard let date = HTTPDateFormatter.date(from: value, now: now) else { return nil }
    let delay = date.timeIntervalSince(now)
    guard delay.isFinite else { return nil }
    return normalizedRetryAfterHeaderSeconds(max(0, delay))
}

private func normalizedRetryAfterHeaderSeconds(_ value: TimeInterval?) -> TimeInterval? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return min(max(value, 15), 15 * 60)
}

private enum HTTPDateFormatter {
    private static let rfc850Weekdays = [
        "Monday,", "Tuesday,", "Wednesday,", "Thursday,", "Friday,", "Saturday,", "Sunday,"
    ]

    static func date(from value: String, now: Date) -> Date? {
        if let date = parse(value, format: "EEE, dd MMM yyyy HH:mm:ss z") {
            return date
        }
        if let date = rfc850Date(from: value, now: now) {
            return date
        }
        return parse(value, format: "EEE MMM d HH:mm:ss yyyy")
    }

    private static func rfc850Date(from value: String, now: Date) -> Date? {
        let fields = value.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 4,
              rfc850Weekdays.contains(String(fields[0])) else {
            return nil
        }
        let dateFields = fields[1].split(separator: "-", omittingEmptySubsequences: false)
        guard dateFields.count == 3,
              dateFields[2].count == 2,
              let yearSuffix = Int(dateFields[2]),
              (0...99).contains(yearSuffix) else {
            return nil
        }

        let calendar = utcGregorianCalendar()
        let nowYear = calendar.component(.year, from: now)
        let currentCentury = nowYear - nowYear % 100
        let candidateYears = [currentCentury - 100, currentCentury, currentCentury + 100]
            .map { $0 + yearSuffix }
        let candidates = candidateYears.compactMap { year in
            let expanded = "\(dateFields[0])-\(dateFields[1])-\(year) \(fields[2]) \(fields[3])"
            return parse(expanded, format: "dd-MMM-yyyy HH:mm:ss z")
        }
        guard let futureLimit = calendar.date(byAdding: .year, value: 50, to: now) else {
            return nil
        }
        if let future = candidates.filter({ $0 >= now }).min(), future <= futureLimit {
            return future
        }
        return candidates.filter { $0 < now }.max()
    }

    private static func parse(_ value: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utcGregorianCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private static func utcGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
