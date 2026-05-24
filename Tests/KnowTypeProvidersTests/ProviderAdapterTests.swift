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

private actor SequencedMockHTTPClient: HTTPClient {
    private struct Stub {
        var data: Data
        var statusCode: Int
    }

    private var stubs: [Stub]
    private var captured: [URLRequest] = []

    init(responses: [(json: String, statusCode: Int)]) {
        self.stubs = responses.map { response in
            Stub(data: Data(response.json.utf8), statusCode: response.statusCode)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured.append(request)
        guard !stubs.isEmpty else {
            throw ProviderError.invalidResponse("missing mock response")
        }
        let stub = stubs.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (stub.data, response)
    }

    func capturedRequests() -> [URLRequest] {
        captured
    }
}

private func requestBodyObject(
    _ request: URLRequest?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [String: Any] {
    let body = try XCTUnwrap(request?.httpBody, file: file, line: line)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any], file: file, line: line)
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

    func testPromptBuilderUsesContinuationSpecificSuffixPrompt() {
        let continuation = PromptBuilder.systemPrompt(for: .continuation)
        let correction = PromptBuilder.systemPrompt(for: .correction)
        let contextDigest = PromptBuilder.systemPrompt(for: .contextDigest)
        let polish = PromptBuilder.systemPrompt(for: .polish)

        XCTAssertTrue(continuation.contains("suffix generator"))
        XCTAssertTrue(continuation.contains("lockedPrefix"))
        XCTAssertTrue(continuation.contains("candidateHints"))
        XCTAssertTrue(continuation.contains("not selected text"))
        XCTAssertTrue(continuation.contains("do not need to copy any hint exactly"))
        XCTAssertTrue(continuation.contains("Empty candidates are allowed only"))
        XCTAssertTrue(continuation.contains("complete commit-ready recommendation"))
        XCTAssertTrue(continuation.contains(#"lockedPrefix="我觉得这个方案" text="还可以再细化一下。""#))
        XCTAssertTrue(continuation.contains(#"lockedPrefix=null rawInput="this approach""#))
        XCTAssertFalse(continuation.contains("Chinese continuation"))
        XCTAssertFalse(correction.contains("suffix generator"))
        XCTAssertFalse(contextDigest.contains("suffix only"))
        XCTAssertFalse(polish.contains("suffix generator"))
    }

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
        let bodyObject = try requestBodyObject(request)
        let responseFormat = try XCTUnwrap(bodyObject["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, PromptBuilder.systemPrompt(for: .continuation))
        XCTAssertEqual(response.candidates.first?.text, "还有进一步优化空间")
    }

    func testOpenAIChatFallsBackToJSONModeWhenStructuredOutputIsUnsupported() async throws {
        await StructuredOutputCapabilityCache.shared.reset()
        let content = #"{"candidates":[{"text":"还有进一步优化空间","confidence":0.9,"reason":"ok"}]}"#
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"error":{"message":"response_format json_schema is unsupported"}}"#, statusCode: 400),
            (json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#, statusCode: 200)
        ])
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "https://fallback-chat.example.com")!,
                apiKey: "key",
                model: "fallback-model"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()

        XCTAssertEqual(requests.count, 2)
        let firstBody = try requestBodyObject(requests[0])
        let firstFormat = try XCTUnwrap(firstBody["response_format"] as? [String: Any])
        XCTAssertEqual(firstFormat["type"] as? String, "json_schema")
        let secondBody = try requestBodyObject(requests[1])
        let secondFormat = try XCTUnwrap(secondBody["response_format"] as? [String: Any])
        XCTAssertEqual(secondFormat["type"] as? String, "json_object")
        XCTAssertEqual(response.diagnostics, ["structured_schema_unsupported"])
        XCTAssertEqual(response.candidates.first?.text, "还有进一步优化空间")
    }

    func testStructuredFallbackClassifierRequiresSchemaSpecificError() {
        XCTAssertFalse(StructuredOutputFallback.isStructuredSchemaUnsupported(
            ProviderError.httpStatus(400, #"{"error":{"message":"unsupported model: model-x"}}"#)
        ))
        XCTAssertEqual(
            StructuredOutputFallback.fallbackMode(
                for: ProviderError.httpStatus(
                    400,
                    #"{"error":{"message":"response_format json_schema is unsupported"}}"#
                )
            ),
            .jsonObject
        )
        XCTAssertEqual(
            StructuredOutputFallback.fallbackMode(
                for: ProviderError.httpStatus(
                    400,
                    #"{"error":{"message":"Unknown parameter: 'text'"}}"#
                )
            ),
            .promptOnly
        )
        XCTAssertEqual(
            StructuredOutputFallback.fallbackMode(
                for: ProviderError.httpStatus(
                    400,
                    #"{"error":{"message":"Unknown parameter: 'text.format'"}}"#
                )
            ),
            .promptOnly
        )
    }

    func testStructuredFallbackCapabilityKeyIsScopedByAuthContext() {
        let baseConfiguration = ProviderConfiguration(
            kind: .openAIChat,
            baseURL: URL(string: "https://capability.example.com")!,
            apiKey: "key-a",
            model: "model",
            headers: ["X-Tenant": "tenant-a"]
        )
        var differentKey = baseConfiguration
        differentKey.apiKey = "key-b"
        var differentHeader = baseConfiguration
        differentHeader.headers = ["X-Tenant": "tenant-b"]

        let baseKey = StructuredOutputFallback.capabilityKey(
            providerName: "openai_chat",
            configuration: baseConfiguration,
            model: "model"
        )
        let keyScoped = StructuredOutputFallback.capabilityKey(
            providerName: "openai_chat",
            configuration: differentKey,
            model: "model"
        )
        let headerScoped = StructuredOutputFallback.capabilityKey(
            providerName: "openai_chat",
            configuration: differentHeader,
            model: "model"
        )

        XCTAssertNotEqual(baseKey, keyScoped)
        XCTAssertNotEqual(baseKey, headerScoped)
        XCTAssertFalse(baseKey.contains("key-a"))
        XCTAssertFalse(baseKey.contains("tenant-a"))
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
        let request = await client.capturedRequest()
        let bodyObject = try requestBodyObject(request)
        let text = try XCTUnwrap(bodyObject["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(bodyObject["instructions"] as? String, PromptBuilder.systemPrompt(for: .continuation))
        XCTAssertEqual(response.candidates.first?.text, "still needs more validation")
    }

    func testOpenAIResponsesFallsBackToJSONModeWhenSchemaFormatIsUnsupported() async throws {
        await StructuredOutputCapabilityCache.shared.reset()
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"error":{"message":"text.format json_schema is unsupported"}}"#, statusCode: 400),
            (json: #"{"output_text":"{\"candidates\":[{\"text\":\"fallback response\"}]}"}"#, statusCode: 200)
        ])
        let provider = OpenAIResponsesProvider(
            configuration: ProviderConfiguration(
                kind: .openAIResponses,
                baseURL: URL(string: "https://responses-json-fallback.example.com")!,
                apiKey: "key",
                model: "model"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()
        let retryBody = try requestBodyObject(requests[1])
        let text = try XCTUnwrap(retryBody["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(format["type"] as? String, "json_object")
        XCTAssertEqual(response.diagnostics, ["structured_schema_unsupported"])
        XCTAssertEqual(response.candidates.first?.text, "fallback response")
    }

    func testOpenAIResponsesFallsBackToPromptOnlyWhenTextFieldIsUnsupported() async throws {
        await StructuredOutputCapabilityCache.shared.reset()
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"error":{"message":"Unknown parameter: 'text'"}}"#, statusCode: 400),
            (json: #"{"output_text":"{\"candidates\":[{\"text\":\"prompt only fallback\"}]}"}"#, statusCode: 200)
        ])
        let provider = OpenAIResponsesProvider(
            configuration: ProviderConfiguration(
                kind: .openAIResponses,
                baseURL: URL(string: "https://responses-prompt-fallback.example.com")!,
                apiKey: "key",
                model: "model"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()
        let firstBody = try requestBodyObject(requests[0])
        let retryBody = try requestBodyObject(requests[1])

        XCTAssertEqual(requests.count, 2)
        XCTAssertNotNil(firstBody["text"] as? [String: Any])
        XCTAssertNil(retryBody["text"])
        XCTAssertEqual(response.diagnostics, ["structured_schema_unsupported"])
        XCTAssertEqual(response.candidates.first?.text, "prompt only fallback")
    }

    func testStructuredResponseNormalizerRejectsNonSchemaCandidateOutput() throws {
        let valid = #"{"candidates":[{"text":"继续推进","confidence":0.9,"reason":"ok"}]}"#
        let response = try StructuredResponseNormalizer.normalizeText(valid, task: .continuation)
        XCTAssertEqual(response.candidates.first?.text, "继续推进")

        XCTAssertThrowsError(
            try StructuredResponseNormalizer.normalizeText("继续推进", task: .continuation)
        ) { error in
            XCTAssertEqual(error as? ProviderError, .invalidResponse("structured_decode_error: invalid JSON object"))
        }
        XCTAssertThrowsError(
            try StructuredResponseNormalizer.normalizeText(#"{"text":"继续推进"}"#, task: .continuation)
        ) { error in
            XCTAssertEqual(error as? ProviderError, .invalidResponse("structured_decode_error: unexpected candidate response fields"))
        }
        XCTAssertThrowsError(
            try StructuredResponseNormalizer.normalizeText(
                #"{"candidates":[{"text":123,"confidence":0.9,"reason":"bad"}]}"#,
                task: .continuation
            )
        ) { error in
            XCTAssertEqual(error as? ProviderError, .invalidResponse("structured_decode_error: candidate text is missing or not a string"))
        }
    }

    func testStructuredResponseNormalizerParsesContextDigestMarkdownObject() throws {
        let response = try StructuredResponseNormalizer.normalizeText(
            "{\"markdown\":\"## Global Style\\n- Concise.\"}",
            task: .contextDigest
        )

        XCTAssertEqual(response.candidates.first?.text, "## Global Style\n- Concise.")
    }

    func testGeminiRequestIncludesStructuredResponseSchema() async throws {
        let content = #"{"candidates":[{"text":"继续推进","confidence":0.9,"reason":"ok"}]}"#
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
        let client = MockHTTPClient(json: #"{"candidates":[{"content":{"parts":[{"text":"\#(escaped)"}]}}]}"#)
        let provider = GeminiNativeProvider(
            configuration: ProviderConfiguration(
                kind: .geminiNative,
                baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                apiKey: "key",
                model: "gemini-test"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()
        let bodyObject = try requestBodyObject(request)
        let generationConfig = try XCTUnwrap(bodyObject["generationConfig"] as? [String: Any])
        let contents = try XCTUnwrap(bodyObject["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let prompt = try XCTUnwrap(parts.first?["text"] as? String)

        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        XCTAssertNotNil(generationConfig["responseSchema"] as? [String: Any])
        XCTAssertTrue(prompt.hasPrefix(PromptBuilder.systemPrompt(for: .continuation)))
        XCTAssertEqual(response.candidates.first?.text, "继续推进")
    }

    func testAnthropicRequestIncludesStructuredOutputConfig() async throws {
        await StructuredOutputCapabilityCache.shared.reset()
        let content = #"{"candidates":[{"text":"继续推进","confidence":0.9,"reason":"ok"}]}"#
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
        let client = MockHTTPClient(json: #"{"content":[{"type":"text","text":"\#(escaped)"}]}"#)
        let provider = AnthropicMessagesProvider(
            configuration: ProviderConfiguration(
                kind: .anthropicMessages,
                baseURL: URL(string: "https://api.anthropic.com")!,
                apiKey: "key",
                model: "claude-test"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let request = await client.capturedRequest()
        let bodyObject = try requestBodyObject(request)
        let outputConfig = try XCTUnwrap(bodyObject["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])

        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(bodyObject["system"] as? String, PromptBuilder.systemPrompt(for: .continuation))
        XCTAssertEqual(response.candidates.first?.text, "继续推进")
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

    func testPlainTextContextDigestPreservesFullMarkdownAsOneCandidate() throws {
        let markdown = """
        ## Global Style
        - Uses concise text.

        ## App Habits
        - TextEdit: writes short notes.
        """

        let response = try ResponseNormalizer.normalizeText(markdown, preservePlainText: true)

        XCTAssertEqual(response.candidates.count, 1)
        XCTAssertEqual(response.candidates.first?.text, markdown)
    }

    func testOpenAIChatDiscoversBlankModelBeforeCompletion() async throws {
        let content = #"{"candidates":[{"text":"本地模型返回的续写"}]}"#
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"object":"list","data":[{"id":"local-model-a"},{"id":"local-model-b"}]}"#, statusCode: 200),
            (json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#, statusCode: 200)
        ])
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://localhost:8000/v1")!,
                apiKey: "local-key",
                model: " \n ",
                headers: ["X-Local-Runtime": "1"]
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()

        XCTAssertEqual(response.candidates.first?.text, "本地模型返回的续写")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertEqual(requests.first?.url?.absoluteString, "http://localhost:8000/v1/models")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer local-key")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-Local-Runtime"), "1")
        XCTAssertEqual(requests.last?.url?.absoluteString, "http://localhost:8000/v1/chat/completions")
        let body = try XCTUnwrap(requests.last?.httpBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(bodyObject["model"] as? String, "local-model-a")
    }

    func testOpenAIChatDiscoverySkipsClearlyNonCompletionModels() async throws {
        let content = #"{"candidates":[{"text":"completion model response"}]}"#
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"gpt-image-2"},{"id":"text-embedding-3-small"},{"id":"nomic-embed-text"},{"id":"mxbai-embed-large"},{"id":"local-chat-model"}]}"#, statusCode: 200),
            (json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#, statusCode: 200)
        ])
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://localhost:8000/v1")!,
                model: ""
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()
        let body = try XCTUnwrap(requests.last?.httpBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(response.candidates.first?.text, "completion model response")
        XCTAssertEqual(bodyObject["model"] as? String, "local-chat-model")
    }

    func testOpenAIModelDiscoveryAllowsEmbedSubstringInCompletionModelName() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"embedded-chat-model"},{"id":"local-chat-model"}]}"#, statusCode: 200)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)

        let model = try await discovery.resolvedModel(
            for: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://localhost:8000")!,
                model: ""
            )
        )

        XCTAssertEqual(model, "embedded-chat-model")
    }

    func testOpenAIChatDiscoveryNormalizesTrailingV1BaseURL() async throws {
        let content = #"{"candidates":[{"text":"local continuation"}]}"#
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"object":"list","data":[{"id":"local-model"}]}"#, statusCode: 200),
            (json: #"{"choices":[{"message":{"content":"\#(content.replacingOccurrences(of: "\"", with: "\\\""))"}}]}"#, statusCode: 200)
        ])
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://localhost:8000/v1/")!,
                model: ""
            ),
            httpClient: client
        )

        _ = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()

        XCTAssertEqual(requests.compactMap { $0.url?.absoluteString }, [
            "http://localhost:8000/v1/models",
            "http://localhost:8000/v1/chat/completions"
        ])
    }

    func testOpenAIResponsesDiscoversPlaceholderModelBeforeCompletion() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"responses-local-model"}]}"#, statusCode: 200),
            (json: #"{"output_text":"{\"candidates\":[{\"text\":\"response continuation\"}]}"}"#, statusCode: 200)
        ])
        let provider = OpenAIResponsesProvider(
            configuration: ProviderConfiguration(
                kind: .openAIResponses,
                baseURL: URL(string: "http://localhost:8000")!,
                model: "<model-id>"
            ),
            httpClient: client
        )

        let response = try await provider.complete(llmRequest)
        let requests = await client.capturedRequests()

        XCTAssertEqual(response.candidates.first?.text, "response continuation")
        XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/v1/models", "/v1/responses"])
        let body = try XCTUnwrap(requests.last?.httpBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(bodyObject["model"] as? String, "responses-local-model")
    }

    func testOpenAIModelDiscoveryRejectsRemoteBlankModel() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"should-not-be-used"}]}"#, statusCode: 200)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)

        do {
            _ = try await discovery.resolvedModel(
                for: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "https://api.openai.com")!,
                    apiKey: "remote-key",
                    model: " \n "
                )
            )
            XCTFail("Expected remote blank model discovery to be rejected")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .invalidResponse("model is required for remote OpenAI-compatible providers")
            )
        }

        let requests = await client.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testOpenAIModelDiscoveryCacheIsScopedByAPIKey() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"model-for-key-a"}]}"#, statusCode: 200),
            (json: #"{"data":[{"id":"model-for-key-b"}]}"#, statusCode: 200)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)
        let baseConfiguration = ProviderConfiguration(
            kind: .openAIChat,
            baseURL: URL(string: "http://localhost:8000")!,
            model: ""
        )

        var keyAConfiguration = baseConfiguration
        keyAConfiguration.apiKey = "key-a"
        var keyBConfiguration = baseConfiguration
        keyBConfiguration.apiKey = "key-b"

        let first = try await discovery.resolvedModel(for: keyAConfiguration)
        let second = try await discovery.resolvedModel(for: keyBConfiguration)
        let cachedFirst = try await discovery.resolvedModel(for: keyAConfiguration)
        let requests = await client.capturedRequests()

        XCTAssertEqual(first, "model-for-key-a")
        XCTAssertEqual(second, "model-for-key-b")
        XCTAssertEqual(cachedFirst, "model-for-key-a")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer key-a",
            "Bearer key-b"
        ])
    }

    func testOpenAIModelDiscoveryThrowsForEmptyModelList() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"object":"list","data":[]}"#, statusCode: 200)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)

        do {
            _ = try await discovery.resolvedModel(
                for: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "http://localhost:8000")!,
                    model: ""
                )
            )
            XCTFail("Expected empty model discovery to throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidResponse("empty models data"))
        }
    }

    func testOpenAIModelDiscoveryThrowsWhenOnlyNonCompletionModelsExist() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":[{"id":"gpt-image-2"},{"id":"text-embedding-3-small"},{"id":"nomic-embed-text"},{"id":"mxbai-embed-large"}]}"#, statusCode: 200)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)

        do {
            _ = try await discovery.resolvedModel(
                for: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "http://localhost:8000")!,
                    model: ""
                )
            )
            XCTFail("Expected non-completion model discovery to throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidResponse("no completion-capable models data"))
        }
    }

    func testOpenAIModelDiscoveryThrowsForHTTPError() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"error":"model list unavailable"}"#, statusCode: 503)
        ])
        let discovery = OpenAICompatibleModelDiscovery(httpClient: client)

        do {
            _ = try await discovery.resolvedModel(
                for: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "http://localhost:8000")!,
                    model: "{{model}}"
                )
            )
            XCTFail("Expected HTTP model discovery failure to throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .httpStatus(503, #"{"error":"model list unavailable"}"#))
        }
    }

    func testOpenAIProviderRequestThrowsForInvalidModelDiscoveryJSON() async throws {
        let client = SequencedMockHTTPClient(responses: [
            (json: #"{"data":"not a model array"}"#, statusCode: 200)
        ])
        let provider = OpenAIChatProvider(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://localhost:8000")!,
                model: "placeholder"
            ),
            httpClient: client
        )

        do {
            _ = try await provider.complete(llmRequest)
            XCTFail("Expected invalid discovery JSON to throw before completion")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidResponse("missing models data"))
        }

        let requests = await client.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/v1/models")
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
        let bodyObject = try requestBodyObject(request)
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])

        XCTAssertEqual(request?.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(messages.first?["content"] as? String, PromptBuilder.systemPrompt(for: .continuation))
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
