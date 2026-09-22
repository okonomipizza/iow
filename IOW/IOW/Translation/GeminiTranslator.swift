//
//  GeminiTranslator.swift
//  IOW
//
//  Gemini API を直接叩く `Translator` / `Simplifier` 実装。
//  BYOK（bring your own key）で、Keychain から読んだユーザーの API キーを
//  `GeminiAPIClient` が使い、プロンプトは `TranslationPrompt` / `SimplifyPrompt`
//  が構築する。
//

import Foundation

/// Gemini の `streamGenerateContent` を叩く `Translator` / `Simplifier`。
struct GeminiTranslator: Translator, Simplifier {

    private let client: GeminiAPIClient
    private let model: String

    /// - Parameters:
    ///   - client: Gemini API クライアント。テスト差し替え用。
    ///   - model: 使用するモデル名。既定は `GeminiAPIConfig.defaultModel`。
    init(client: GeminiAPIClient = GeminiAPIClient(), model: String = GeminiAPIConfig.defaultModel) {
        self.client = client
        self.model = model
    }

    func translate(_ text: String, to target: Language) -> AsyncThrowingStream<String, Error> {
        .cancellable { continuation in
            try await streamTranslation(
                text: text,
                target: target,
                continuation: continuation
            )
        }
    }

    func simplify(_ text: String) -> AsyncThrowingStream<String, Error> {
        .cancellable { continuation in
            try await streamSimplification(
                text: text,
                continuation: continuation
            )
        }
    }

    /// 入力検証ののち Gemini の SSE を中継する。
    ///
    /// ローカル LLM 対応などで別のエンジンへ差し替えても、ここで受けた
    /// 検証（空入力）は翻訳の前提なので変わらない。
    private func streamTranslation(
        text: String,
        target: Language,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyInput
        }

        do {
            try await client.streamGenerateContent(
                model: model,
                systemInstruction: TranslationPrompt.systemPrompt(target: target.code),
                messages: TranslationPrompt.messages(text: trimmed),
                temperature: GeminiAPIConfig.translateTemperature,
                maxTokens: GeminiAPIConfig.translateMaxTokens,
                continuation: continuation
            )
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.engineFailure(underlying: error)
        }
    }

    /// 空入力だけ弾く（簡易化は言語を変えない前提）。
    private func streamSimplification(
        text: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyInput
        }

        do {
            try await client.streamGenerateContent(
                model: model,
                systemInstruction: SimplifyPrompt.systemPrompt(),
                messages: SimplifyPrompt.messages(text: trimmed),
                temperature: GeminiAPIConfig.simplifyTemperature,
                maxTokens: GeminiAPIConfig.simplifyMaxTokens,
                continuation: continuation
            )
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.engineFailure(underlying: error)
        }
    }
}
