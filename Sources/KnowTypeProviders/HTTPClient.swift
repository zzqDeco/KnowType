import Foundation

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
        let body = String(data: data, encoding: .utf8) ?? ""
        throw ProviderError.httpStatus(response.statusCode, body)
    }
}

func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
