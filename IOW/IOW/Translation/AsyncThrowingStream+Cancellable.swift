//
//  AsyncThrowingStream+Cancellable.swift
//  IOW
//
//  ストリーミング応答を返すエンジン（GeminiTranslator）で使う雛形を 1 箇所へ集約する。
//

import Foundation

extension AsyncThrowingStream where Failure == Error {

    /// 破棄したら生成側も畳むストリームを作る。
    ///
    /// `produce` を Task で走らせ、正常終了なら `finish()`、送出されたエラーは
    /// `finish(throwing:)` でストリームへ載せる。加えて `onTermination` でその Task を
    /// キャンセルする。
    ///
    /// `onTermination` が要るのは、ストリームを捨てても生成側が止まらないため。
    /// 訳文ポップアップを閉じても Gemini は生成を続け、こちらは使わない結果に
    /// トークンを払い続けることになる（BYOK ではユーザー自身のキーであり、
    /// 原価はそのままユーザーの請求に載る）。
    ///
    /// - Parameter produce: 差分を `continuation.yield(_:)` へ流す処理。
    ///   終了とエラー処理はこの関数が引き受けるため、`produce` の中で
    ///   `finish()` を呼ぶ必要はない。
    /// - Returns: `produce` の出力を流すストリーム。
    static func cancellable(
        _ produce: @escaping @Sendable (Continuation) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await produce(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
