//
//  GeminiAPIClientTests.swift
//  IOWTests
//
//  Gemini API の SSE を読む経路の検証。
//
//  ここは誤ると不完全な訳文が「正常な翻訳」としてユーザーへ渡る箇所である。
//  `finishReason: STOP` を受け取ったときだけ成功として扱う、という契約が
//  守られなくなると、途中で切れた訳文や空文字がそのまま画面上の結果になる。
//  人手の疎通確認だけでは退行を検出できない。
//

import Foundation
import Testing
@testable import IOW

// MARK: - スタブ

/// 応答を差し替える `URLProtocol`。
///
/// 実サーバーを立てずに SSE の本文とステータスを組み立てるために使う。
/// 応答は `URLProtocolStub.handler` から取り出す。
final class URLProtocolStub: URLProtocol, @unchecked Sendable {

    /// 返すレスポンス（ステータスと本文）。テストごとに差し替える。
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    /// 最後に受け取ったリクエスト。ヘッダやボディの検証に使う。
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolStub.lastRequest = request

        guard let handler = URLProtocolStub.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (statusCode, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 応答と API キーを差し替えたクライアントを作る。
///
/// Keychain には一切触れない。`keyProvider` をクロージャで渡せるようにしてあるので、
/// 実ストアを使う必要がない。
///
/// - Parameter key: `nil` を渡すと未設定（`itemNotFound`）として振る舞う。
private func makeStubbedClient(
    key: String? = "test_gemini_key",
    handler: @escaping @Sendable (URLRequest) -> (Int, Data)
) -> GeminiAPIClient {
    URLProtocolStub.handler = handler
    URLProtocolStub.lastRequest = nil

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]

    return GeminiAPIClient(
        keyProvider: {
            guard let key else { throw KeychainStoreError.itemNotFound }
            return key
        },
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    )
}

/// `URLProtocol` に届いたリクエストの本文を読む。
///
/// `URLProtocol` へ渡る `URLRequest` の `httpBody` は nil で、本文は
/// `httpBodyStream` にある。
func readBody(of request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}

/// SSE の 1 イベント分の行を作る。
private func sseLine(_ json: String) -> String {
    "data: \(json)\n\n"
}

/// Gemini の生成チャンク（複数 part 可）。
private func chunk(parts: [(text: String, thought: Bool)], finishReason: String? = nil) -> String {
    let partsJSON = parts.map { part in
        let thought = part.thought ? #","thought":true"# : ""
        return #"{"text":"\#(part.text)"\#(thought)}"#
    }
    .joined(separator: ",")
    let finish = finishReason.map { #","finishReason":"\#($0)""# } ?? ""
    return #"{"candidates":[{"content":{"parts":[\#(partsJSON)],"role":"model"}\#(finish),"index":0}]}"#
}

/// ストリームを最後まで読み、連結した文字列を返す。
private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
    var result = ""
    for try await delta in stream {
        result += delta
    }
    return result
}

/// `streamGenerateContent` を単体で呼び、差分を集める。
private func runClient(_ client: GeminiAPIClient, model: String = "gemini-3.5-flash-lite") async throws -> String {
    let stream = AsyncThrowingStream<String, Error> { continuation in
        Task {
            do {
                try await client.streamGenerateContent(
                    model: model,
                    systemInstruction: "system",
                    messages: [.init(content: "Hello")],
                    temperature: 0.2,
                    maxTokens: 12_288,
                    continuation: continuation
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
    return try await collect(stream)
}

// MARK: - テスト

/// スタブは `URLProtocol` のクラス変数を介して応答を渡すため、テスト間で共有される。
/// swift-testing は既定で並列に実行するので、直列化しないと互いの応答を奪い合う。
///
/// - Important: `.serialized` が効くのはこの suite の中だけである。
///   `makeStubbedClient` を別の suite からも使うなら、そちらにも付けること。
@Suite(.serialized)
struct GeminiAPIClientTests {

    @Test func concatenatesDeltasUntilStop() async throws {
        // 正常系。delta を順に受け取り、STOP で終わる。
        let body = sseLine(chunk(parts: [("こん", false)]))
            + sseLine(chunk(parts: [("にちは", false)], finishReason: "STOP"))
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        #expect(try await runClient(client) == "こんにちは")
    }

    @Test func sendsKeyInHeaderAndRequestsSSE() async throws {
        let body = sseLine(chunk(parts: [("x", false)], finishReason: "STOP"))
        let client = makeStubbedClient(key: "specific_key") { _ in (200, Data(body.utf8)) }

        _ = try await runClient(client)

        let request = URLProtocolStub.lastRequest
        #expect(request?.value(forHTTPHeaderField: "x-goog-api-key") == "specific_key")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request?.url?.absoluteString.contains(":streamGenerateContent?alt=sse") == true)
        // キーはヘッダだけで渡す。URL に載せるとログ・リダイレクト・プロキシの
        // 記録へキーが漏れうるため、クエリに `key` が無いことまで見る。
        #expect(request?.url?.query?.contains("key=") != true)
    }

    @Test func requestBodyCarriesSystemInstructionAndGenerationConfig() async throws {
        let body = sseLine(chunk(parts: [("x", false)], finishReason: "STOP"))
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        _ = try await runClient(client)

        // プロンプトの配線。system が systemInstruction へ、本文が contents へ入り、
        // generationConfig に温度・出力上限・思考レベルが載ることを検証する。
        guard let request = URLProtocolStub.lastRequest else {
            Issue.record("No request was captured")
            return
        }
        guard let sentBody = readBody(of: request),
              let object = try? JSONSerialization.jsonObject(with: sentBody) as? [String: Any] else {
            Issue.record("Request body is missing or not a JSON object")
            return
        }

        let systemInstruction = object["systemInstruction"] as? [String: Any]
        let parts = systemInstruction?["parts"] as? [[String: Any]]
        #expect((parts?.first?["text"] as? String) == "system")

        let contents = object["contents"] as? [[String: Any]]
        #expect(contents?.first?["role"] as? String == "user")
        #expect((contents?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String == "Hello")

        let config = object["generationConfig"] as? [String: Any]
        #expect(config?["temperature"] as? Double == 0.2)
        #expect(config?["maxOutputTokens"] as? Int == 12_288)
        let thinking = config?["thinkingConfig"] as? [String: Any]
        #expect(thinking?["thinkingLevel"] as? String == "minimal")
    }

    @Test func excludesThoughtParts() async throws {
        // thought の part は推論の出力であって生成物ではない。そのまま流すと
        // モデルの思考が翻訳文として表示される。
        let body = sseLine(chunk(parts: [("思考の過程", true)]))
            + sseLine(chunk(parts: [("本文", false)], finishReason: "STOP"))
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        #expect(try await runClient(client) == "本文")
    }

    @Test func throwsIncompleteStreamWhenStopIsMissing() async throws {
        // STOP が来ないまま終わったら失敗。ここを成功にすると、途中で切れた訳文が
        // そのまま「正常な翻訳」として返る。
        let body = sseLine(chunk(parts: [("途中まで", false)]))
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.incompleteStream) {
            _ = try await runClient(client)
        }
    }

    @Test func throwsIncompleteStreamWhenNoContentArrives() async throws {
        // STOP だけが来た場合も失敗。空の訳文を成功として返さないため。
        let client = makeStubbedClient { _ in (200, Data(sseLine(chunk(parts: [], finishReason: "STOP")).utf8)) }

        await #expect(throws: GeminiAPIError.incompleteStream) {
            _ = try await runClient(client)
        }
    }

    @Test func throwsIncompleteStreamOnNonStopFinishReason() async throws {
        // 出力上限・安全フィルタで打ち切られた生成は文の途中で終わっており、
        // STOP と同じ扱いをすると不完全な訳文を成功として返す。
        let body = sseLine(chunk(parts: [("途中まで", false)], finishReason: "MAX_TOKENS"))
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.incompleteStream) {
            _ = try await runClient(client)
        }
    }

    @Test func throwsInvalidResponseOnMalformedEvent() async throws {
        // 壊れたイベントを読み飛ばすと、欠けた訳文を正常終了として扱ってしまう。
        let body = sseLine(chunk(parts: [("途中まで", false)])) + "data: {not json\n\n"
        let client = makeStubbedClient { _ in (200, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.invalidResponse) {
            _ = try await runClient(client)
        }
    }

    @Test func mapsInvalidKeyToItsOwnError() async throws {
        // 401 は設定画面へ誘導する必要があるので、他の失敗と区別する。
        let body = #"{"error":{"code":401,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}"#
        let client = makeStubbedClient { _ in (401, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.invalidKey) {
            _ = try await runClient(client)
        }
    }

    @Test func mapsRateLimitToItsOwnError() async throws {
        let body = #"{"error":{"code":429,"message":"Resource has been exhausted.","status":"RESOURCE_EXHAUSTED"}}"#
        let client = makeStubbedClient { _ in (429, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.rateLimited) {
            _ = try await runClient(client)
        }
    }

    @Test func mapsOtherFailuresToServerError() async throws {
        let body = #"{"error":{"code":500,"message":"boom","status":"INTERNAL"}}"#
        let client = makeStubbedClient { _ in (500, Data(body.utf8)) }

        await #expect(throws: GeminiAPIError.serverError(code: "INTERNAL", statusCode: 500)) {
            _ = try await runClient(client)
        }
    }

    @Test func throwsKeyNotConfiguredWhenKeychainIsEmpty() async throws {
        // キー未設定のまま翻訳を試みた場合。設定を促す文言へ繋がる。
        let client = makeStubbedClient(key: nil) { _ in (200, Data()) }

        await #expect(throws: GeminiAPIError.keyNotConfigured) {
            _ = try await runClient(client)
        }
    }

    @Test func doesNotCallGeminiWhenKeyIsMissing() async throws {
        // 未設定なら往復もしない。
        let client = makeStubbedClient(key: nil) { _ in (200, Data()) }

        _ = try? await runClient(client)

        #expect(URLProtocolStub.lastRequest == nil)
    }
}

// MARK: - ユーザー向け文言

struct GeminiAPIErrorMessageTests {

    @Test func keyProblemsPointAtSettings() {
        // 翻訳と簡易化が同じ対応表を使う。
        #expect(GeminiAPIError.keyNotConfigured.userMessage(action: "翻訳").contains("設定"))
        #expect(GeminiAPIError.invalidKey.userMessage(action: "翻訳").contains("設定"))
    }

    @Test func actionNameAppearsInMessage() {
        #expect(GeminiAPIError.incompleteStream.userMessage(action: "簡易化").contains("簡易化"))
        #expect(GeminiAPIError.serverError(code: "x", statusCode: 500).userMessage(action: "翻訳").contains("翻訳"))
    }
}

struct TranslationErrorMessageTests {

    @Test func engineFailureDelegatesToTheApiErrorTable() {
        // GeminiAPIError の文言はあちらの対応表 1 つに集約してある。ここで
        // 文言を書き直すと、また 2 重管理に戻る。
        let error = TranslationError.engineFailure(underlying: GeminiAPIError.keyNotConfigured)
        let message = TranslationError.userMessage(for: error)

        #expect(message == GeminiAPIError.keyNotConfigured.userMessage(action: "翻訳"))
    }

    @Test func unknownErrorsFallBackToAGenericMessage() {
        // 呼び出し側はストリームから任意の Error を受け取る。
        // TranslationError 以外が来ても、内部情報を漏らさない文言で終わること。
        struct Unexpected: Error {}
        let message = TranslationError.userMessage(for: Unexpected())

        #expect(message == "翻訳に失敗しました。")
    }

    @Test func emptyInputAsksForText() {
        let message = TranslationError.userMessage(for: TranslationError.emptyInput)

        #expect(message.contains("入力してください"))
    }
}

// MARK: - GeminiTranslator

struct GeminiTranslatorTests {

    @Test func throwsEmptyInputWhenTranslatingBlankText() async {
        let translator = GeminiTranslator()
        var threwEmptyInput = false
        do {
            for try await _ in translator.translate("   ", to: .english) {}
        } catch TranslationError.emptyInput {
            threwEmptyInput = true
        } catch {}
        #expect(threwEmptyInput)
    }

    @Test func throwsEmptyInputWhenSimplifyingBlankText() async {
        let translator = GeminiTranslator()
        var threwEmptyInput = false
        do {
            for try await _ in translator.simplify("   ") {}
        } catch TranslationError.emptyInput {
            threwEmptyInput = true
        } catch {}
        #expect(threwEmptyInput)
    }
}
