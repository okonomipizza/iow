//
//  Translator.swift
//  IOW
//
//  翻訳エンジンの抽象インターフェース。
//  具体的な翻訳プロバイダ（DeepL / OpenAI 等）に依存しないよう protocol で定義し、
//  実装を差し替え可能にする。
//

import Foundation

/// 翻訳処理中に発生し得るエラー。
enum TranslationError: Error {
    /// 入力テキストが空のため翻訳を実行できない。
    case emptyInput

    /// 翻訳エンジン側で処理に失敗した（ネットワーク・API エラー等）。
    /// `underlying` に元のエラーを保持する。
    case engineFailure(underlying: Error)
}

// MARK: - ユーザー向けの文言

extension TranslationError {

    /// ユーザーへ見せるメッセージ。
    ///
    /// ホットキーのポップアップから使う。`GeminiAPIError` に対応する文言は
    /// あちらの対応表（`userMessage(action:)`）に集約してある（キー未設定・無効は
    /// 設定画面への誘導が要るため、ここと 2 重管理しない）。
    ///
    /// 引数が `Error` なのは、呼び出し側がストリームから受け取るエラーが
    /// `TranslationError` とは限らないため。想定外のエラーは汎用の文言へ落とす。
    ///
    /// 原文・訳文・トークンは含めない。
    ///
    /// - Parameter error: ストリームから受け取ったエラー。
    static func userMessage(for error: Error) -> String {
        switch error {
        case TranslationError.emptyInput:
            return "テキストを入力してください。"
        case TranslationError.engineFailure(let underlying as GeminiAPIError):
            // キー未設定・無効は設定画面へ誘導する必要があるため、
            // 「時間をおいて再度」で片付けない。文言は GeminiAPIError 側に集約する。
            return underlying.userMessage(action: "翻訳")
        case TranslationError.engineFailure:
            return "翻訳に失敗しました。時間をおいて再度お試しください。"
        default:
            return "翻訳に失敗しました。"
        }
    }
}

/// 翻訳エンジンの抽象インターフェース。
///
/// 具体的な翻訳プロバイダ（外部 API など）はこの protocol に準拠して実装する。
/// UI 層はこの protocol にのみ依存するため、プロバイダの差し替えが容易になる。
///
/// - Note: `Sendable` に準拠させ、`translate(_:to:)` を actor 境界を跨いで
///   （UI の `@MainActor` からバックグラウンドへ）安全に呼び出せるようにする。
/// - Note: 各ストリーム要素は「新たに生成された差分テキスト」であり、呼び出し側が順次連結する。
protocol Translator: Sendable {
    /// 与えられたテキストを翻訳し、差分テキストを逐次流す。
    ///
    /// 原文の言語は指定しない。エンジン側（Gemini 等）がテキストから判断する。
    ///
    /// - Parameters:
    ///   - text: 翻訳対象のテキスト。
    ///   - target: 翻訳先の言語。
    /// - Returns: 差分文字列を逐次返すストリーム。入力バリデーションや API エラーは
    ///   `finish(throwing:)` で終了する。エラー型は `TranslationError` を含む。
    func translate(_ text: String, to target: Language) -> AsyncThrowingStream<String, Error>
}

/// 簡易化エンジンの抽象インターフェース。
///
/// 原文の言語を変えずにやさしい表現へ書き換える。翻訳とは別のプロンプトと
/// バリデーション（同言語スキップなし）を持つため、`Translator` とは分ける。
protocol Simplifier: Sendable {
    /// 与えられたテキストを簡易化し、差分テキストを逐次流す。
    ///
    /// - Parameter text: 簡易化対象のテキスト。
    /// - Returns: 差分文字列を逐次返すストリーム。空入力などは
    ///   `TranslationError` で終了する。
    func simplify(_ text: String) -> AsyncThrowingStream<String, Error>
}
