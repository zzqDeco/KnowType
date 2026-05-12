import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeProviders

private actor MockHTTPClient: HTTPClient {
    private let dataValue: Data
    private let statusCode: Int
    private var captured: URLRequest?

    init(json: String, statusCode: Int = 200) {
        self.dataValue = Data(json.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (dataValue, response)
    }

    func capturedRequest() -> URLRequest? {
        captured
    }
}

final class ProviderAdapterTests: XCTestCase {
    private let llmRequest = LLMRequest(
        task: .continuation,
        lockedPrefix: "我觉得这个方案",
        rawInput: "wo jue de zhege fagnan",
        locale: .zhCN,
        maxCandidates: 3,
        lengthLevel: .medium
    )

    func testOpenAIChatMapsRequestAndParsesCandidates() async throws {
        let content = #"{"candidates":[{"text":"还有进一步优化空间","confidence":0.9}]}"#
        let client = MockHTTPClient(json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#)
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "https://api.example.com")!,
                apiKey: "key",
                model: "model"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        XCTAssertEqual(response.candidates.first?.text, "还有进一步优化空间")
    }

    func testOpenAIResponsesParsesOutputText() async throws {
        let client = MockHTTPClient(json: #"{"output_text":"{\"candidates\":[{\"text\":\"still needs more validation\"}]}"}"#)
        let provider = OpenAIResponsesProvider(
            configuration: ProviderConfiguration(
                kind: .openAIResponses,
                baseURL: URL(string: "https://api.example.com")!,
                apiKey: "key",
                model: "model"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        XCTAssertEqual(response.candidates.first?.text, "still needs more validation")
    }

    func testOpenAICompatibleBaseURLMayIncludeV1() async throws {
        let content = #"{"candidates":[{"text":"还有进一步优化空间"}]}"#
        let client = MockHTTPClient(json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#)
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "https://api.example.com/v1")!,
                model: "model"
            ),
            httpClient: client
        )

        _ = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testAnthropicMessagesUsesNativeHeaders() async throws {
        let client = MockHTTPClient(json: #"{"content":[{"type":"text","text":"{\"candidates\":[{\"text\":\"could be simplified further\"}]}"}]}"#)
        let provider = AnthropicMessagesProvider(
            configuration: ProviderConfiguration(
                kind: .anthropicMessages,
                baseURL: URL(string: "https://api.anthropic.example")!,
                apiKey: "anthropic-key",
                model: "claude"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.example/v1/messages")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(response.candidates.first?.text, "could be simplified further")
    }

    func testGeminiNativeMapsGenerateContentEndpoint() async throws {
        let client = MockHTTPClient(json: #"{"candidates":[{"content":{"parts":[{"text":"{\"candidates\":[{\"text\":\"需要先验证核心假设\"}]}"}]}}]}"#)
        let provider = GeminiNativeProvider(
            configuration: ProviderConfiguration(
                kind: .geminiNative,
                baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                apiKey: "gemini-key",
                model: "gemini-pro"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.url?.path, "/v1beta/models/gemini-pro:generateContent")
        XCTAssertEqual(request?.url?.query, "key=gemini-key")
        XCTAssertEqual(response.candidates.first?.text, "需要先验证核心假设")
    }

    func testOllamaNativeParsesMessageContent() async throws {
        let client = MockHTTPClient(json: #"{"message":{"role":"assistant","content":"{\"candidates\":[{\"text\":\"may introduce extra complexity\"}]}"},"done":true}"#)
        let provider = OllamaNativeProvider(
            configuration: ProviderConfiguration(
                kind: .ollamaNative,
                baseURL: URL(string: "http://localhost:11434")!,
                model: "llama"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(response.candidates.first?.text, "may introduce extra complexity")
    }

    func testCustomHTTPTemplateAndResponsePath() async throws {
        let client = MockHTTPClient(json: #"{"result":{"items":[{"text":"核心假设还需要进一步验证"}]}}"#)
        let provider = CustomHTTPProvider(
            configuration: ProviderConfiguration(
                kind: .customHTTP,
                baseURL: URL(string: "https://custom.example/infer")!,
                apiKey: "custom-key",
                model: "custom",
                customBodyTemplate: #"{"task":"{{task}}","prefix":"{{locked_prefix}}","n":{{max_candidates}}}"#,
                customResponsePath: "result.items"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()
        let body = String(data: request?.httpBody ?? Data(), encoding: .utf8)

        XCTAssertEqual(body, #"{"task":"continuation","prefix":"我觉得这个方案","n":3}"#)
        XCTAssertEqual(response.candidates.first?.text, "核心假设还需要进一步验证")
    }
}
