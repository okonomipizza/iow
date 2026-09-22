//
//  GeminiAPIClient.swift
//  IOW
//
//  Gemini API（native の `streamGenerateContent`）を直接叩くクライアント。
//  BYOK（bring your own key）で、アプリがユーザーの API キーを Keychain から
//  読んで Gemini へ直接接続する。
//

import Foundation

/// Gemini API の接続先と、リクエストに関する定数。
enum GeminiAPIConfig {

    /// Gemini API のベース URL（末尾スラッシュなし）。
    ///
    /// 接続先は固定の Google の API のため、ここにリテラルで置く。
    /// ローカル LLM 対応（Ollama 等）が決まったときは、この値を設定で差し替える
    /// 形に拡張する。
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    /// 既定のモデル。
    ///
    /// 翻訳の品質・速度を実測で確認したフラッシュ系。
    /// モデルの切り替えはこの行の変更（または将来の設定項目）で済む。
    static let defaultModel = "gemini-3.5-flash-lite"

    /// 翻訳のブレを抑えるため低めの temperature。
    static let translateTemperature = 0.2

    /// 簡易化のブレを抑えるため低めの temperature（翻訳と同程度）。
    static let simplifyTemperature = 0.2

    /// 翻訳の出力上限（トークン）。原本の上限（10,000 字）を訳し切れる余裕から決める。
    static let translateMaxTokens = 12_288

    /// 簡易化の出力上限（トークン）。原文と同程度の長さを想定し翻訳と同じ。
    static let simplifyMaxTokens = 12_288

    /// 推論の深さ。`minimal` で思考トークンが 0 になる（実測で確認済み）。
    ///
    /// 翻訳にも簡易化にも推論は要らず、思考が入ると TTFT が跳ね上がる。
    static let thinkingLevel = "minimal"
}

/// Gemini API 呼び出しで発生するエラー。
///
/// `TranslationError.engineFailure(underlying:)` に載せて UI まで運ぶ。
/// UI 側は `invalidKey` と `keyNotConfigured` を他と区別し、設定画面へ誘導する。
enum GeminiAPIError: Error, Sendable, Equatable {
    /// Keychain に API キーが未保存。
    case keyNotConfigured

    /// API キーが無効（Gemini が 401 を返した）。
    case invalidKey

    /// 利用が多すぎる（Gemini が 429 を返した）。
    case rateLimited

    /// Gemini が上記以外の失敗を返した。
    case serverError(code: String, statusCode: Int)

    /// ストリームの途中で Gemini が error を返した。
    case streamFailed

    /// ストリームが正常に完結しなかった。
    ///
    /// `finishReason: STOP` を受け取らないまま途切れた場合と、受け取ったが
    /// 内容が 1 文字も届かなかった場合の両方を指す。
    ///
    /// Gemini の契約では、`finishReason: STOP` が来たときだけ成功として扱う。
    /// 途中で切れた訳文や空文字を成功として返すと、アプリが不完全な結果を
    /// ユーザーへ「正常な翻訳」として表示し続けることになる。
    case incompleteStream

    /// レスポンスの形が想定と違う。
    case invalidResponse
}

/// Gemini API へ送るメッセージ（`contents` の要素）。
///
/// Gemini は system を会話の中に置かず `systemInstruction` として別に受け取る
/// ため、ここに持つのは本文だけである。
///
/// 役割（`role`）を型に持たないのは、このアプリが送るのが常に 1 往復の user
/// ターンだけだからである（`makeRequestBody` が `"user"` を直に書く）。
/// 多ターンへ戻すなら、そのときに役割をここへ足す。
struct GeminiMessage: Sendable, Equatable {
    let content: String
}

/// Gemini が SSE で返す 1 ラインの data ペイロード。
///
/// チャンクの形は `{ candidates: [{ content: { parts: [{ text, thought }] },
/// finishReason }], usageMetadata }` である。各フィールドは欠けうるため、
/// 全体を任意で受ける。
private struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
                let thought: Bool?
            }

            let parts: [Part]?
        }

        let content: Content?
        let finishReason: String?
    }

    /// エラー（ヘッダ送出前は `{ "error": { "code", "status", "message" } }`）。
    struct ErrorPayload: Decodable {
        let code: Int?
        let message: String?
    }

    let candidates: [Candidate]?
    let error: ErrorPayload?
}

/// Gemini がヘッダ送出前の失敗で返す JSON。
private struct GeminiErrorResponse: Decodable {
    struct Payload: Decodable {
        let code: Int?
        let status: String?
        let message: String?
    }

    let error: Payload?
}

/// Gemini API の `streamGenerateContent` を叩き、差分テキストを流す。
struct GeminiAPIClient: Sendable {

    /// 正常終了を表す `finishReason`。これ以外はすべて中断として扱う。
    private static let normalFinishReason = "STOP"

    /// キーの取得元。
    ///
    /// 既定は Keychain だが、クロージャで受けることでテストが Keychain へ
    /// 一切触れずに済む。
    ///
    /// 未設定を表すには `KeychainStoreError.itemNotFound` を投げる。
    typealias KeyProvider = @Sendable () throws -> String

    private let keyProvider: KeyProvider
    private let session: URLSession
    private let baseURL: URL

    /// - Parameters:
    ///   - keyProvider: Gemini API キーの取得。既定は Keychain から読む
    ///     （account 名は `APIKeyProvider` が持つ）。
    ///   - session: HTTP クライアント。テスト差し替え用。
    ///   - baseURL: Gemini API のベース URL。テスト差し替え用。
    init(
        keyProvider: @escaping KeyProvider = { try KeychainStore(account: APIKeyProvider.geminiAccount).getPassword() },
        session: URLSession = .shared,
        baseURL: URL = GeminiAPIConfig.baseURL
    ) {
        self.keyProvider = keyProvider
        self.session = session
        self.baseURL = baseURL
    }

    /// Gemini へストリーミング生成を依頼し、差分を `continuation` へ流す。
    ///
    /// - Parameters:
    ///   - model: モデル名（例: `gemini-3.5-flash-lite`）。
    ///   - systemInstruction: system プロンプト。無ければ `nil`。
    ///   - messages: user / model のメッセージ列。
    ///   - temperature: generationConfig の temperature。
    ///   - maxTokens: generationConfig の maxOutputTokens。
    ///   - continuation: 差分の流し先。
    func streamGenerateContent(
        model: String,
        systemInstruction: String?,
        messages: [GeminiMessage],
        temperature: Double,
        maxTokens: Int,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let apiKey: String
        do {
            apiKey = try keyProvider()
        } catch KeychainStoreError.itemNotFound {
            throw GeminiAPIError.keyNotConfigured
        } catch {
            throw error
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("models/\(model):streamGenerateContent")
                .appending(queryItems: [URLQueryItem(name: "alt", value: "sse")])
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // API キーは URL のクエリ（`?key=`）ではなくヘッダで渡す。
        // URL はログにもリダイレクトやプロキシの記録にも載りうるため。
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        request.httpBody = try makeRequestBody(
            systemInstruction: systemInstruction,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw try await Self.makeError(statusCode: http.statusCode, bytes: bytes)
        }

        try await Self.consume(bytes: bytes, continuation: continuation)
    }

    /// リクエストボディを組み立てる。
    ///
    /// Gemini のボディは system と会話を分け、`generationConfig` に安定化の
    /// パラメータをまとめる。
    private func makeRequestBody(
        systemInstruction: String?,
        messages: [GeminiMessage],
        temperature: Double,
        maxTokens: Int
    ) throws -> Data {
        var body: [String: Any] = [:]

        if let systemInstruction, !systemInstruction.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemInstruction]]]
        }

        // `role` は Gemini が要求する必須フィールド。送るのは user ターンだけなので
        // 定数で書く（`GeminiMessage` のコメント参照）。
        body["contents"] = messages.map { message in
            [
                "role": "user",
                "parts": [["text": message.content]],
            ]
        }

        body["generationConfig"] = [
            "temperature": temperature,
            "maxOutputTokens": maxTokens,
            "thinkingConfig": ["thinkingLevel": GeminiAPIConfig.thinkingLevel],
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    /// ヘッダ送出前の失敗を `GeminiAPIError` へ写す。
    ///
    /// 本文から `status` フィールドだけを取り出し、ステータスコードで分類する。
    private static func makeError(
        statusCode: Int,
        bytes: URLSession.AsyncBytes
    ) async throws -> GeminiAPIError {
        var payload = Data()
        // エラー本文は小さい。上限を設けて読み切る。
        for try await byte in bytes {
            payload.append(byte)
            if payload.count > 8 * 1024 { break }
        }

        let status = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: payload))?.error?.status
            ?? "unknown"

        switch statusCode {
        case 401:
            // ユーザーの API キーが無効。設定画面へ誘導する必要がある。
            return .invalidKey
        case 429:
            return .rateLimited
        default:
            return .serverError(code: status, statusCode: statusCode)
        }
    }

    /// SSE を読み、`candidates` のパーツを繋いで `finishReason: STOP` で正常終了する。
    private static func consume(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var sawStop = false
        var sawContent = false

        // 1 応答で数百のデルタが届く。イベントごとに作ると、その数だけ
        // インスタンスを捨てることになるのでループの外で使い回す。
        let decoder = JSONDecoder()

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }

            let chunk: GeminiStreamChunk
            do {
                chunk = try decoder.decode(GeminiStreamChunk.self, from: Data(payload.utf8))
            } catch {
                throw GeminiAPIError.invalidResponse
            }

            // ストリーム途中の error。headers 送出前のエラーとは別にここでも
            // 拾える（Google は `{ "error": ... }` を data 行として流しうる）。
            if chunk.error != nil {
                throw GeminiAPIError.streamFailed
            }

            if let candidates = chunk.candidates {
                for candidate in candidates {
                    if let parts = candidate.content?.parts {
                        for part in parts {
                            // thought の part は生成物ではない。そのまま流すと
                            // モデルの思考がユーザーの画面に出る。
                            if part.thought == true {
                                continue
                            }
                            if let text = part.text, !text.isEmpty {
                                sawContent = true
                                continuation.yield(text)
                            }
                        }
                    }
                    if let finishReason = candidate.finishReason {
                        if finishReason == normalFinishReason {
                            sawStop = true
                        } else {
                            // 出力上限や安全フィルタで打ち切られた生成は文の途中で
                            // 終わっており、成功として返すと不完全な訳文を
                            // ユーザーへ「正常な翻訳」として表示してしまう。
                            throw GeminiAPIError.incompleteStream
                        }
                    }
                }
            }

            if sawStop { break }
        }

        // STOP を受け取らずに終わったら失敗として扱う。ここを成功にすると、
        // 途中で切れた訳文を「正常な翻訳」として表示してしまう。
        guard sawStop else {
            throw GeminiAPIError.incompleteStream
        }

        // 1 文字も届かないまま STOP が来た場合も失敗として扱う。
        // ここを成功にすると、空の訳文を「正常な翻訳」として表示し、
        // 再試行しても同じ空文字を返し続ける。
        guard sawContent else {
            throw GeminiAPIError.incompleteStream
        }
    }
}

// MARK: - ユーザー向けの文言

extension GeminiAPIError {

    /// ユーザーへ見せるメッセージ。
    ///
    /// ホットキーのポップアップから、翻訳と簡易化の両方で使う。
    /// 対応表は 1 つに保つ。
    ///
    /// 原文・訳文・API キーは含めない。
    ///
    /// - Parameter action: 失敗した操作の名前（「翻訳」など）。
    func userMessage(action: String) -> String {
        switch self {
        case .keyNotConfigured:
            return "Gemini API キーが未設定です。設定…から保存してください。"
        case .invalidKey:
            return "Gemini API キーが無効です。設定…から保存し直してください。"
        case .rateLimited:
            return "利用が集中しています。しばらく待ってからお試しください。"
        case .incompleteStream:
            return "\(action)が途中で途切れました。もう一度お試しください。"
        case .streamFailed:
            return "\(action)に失敗しました。ネットワークを確認してください。"
        case .serverError, .invalidResponse:
            return "\(action)に失敗しました。ネットワークを確認してください。"
        }
    }
}
