//
//  SimplifyPrompt.swift
//  IOW
//
//  簡易化（Simplify）用プロンプトの構築。
//
//  原文の言語は変えず、より短い文・平易な語彙へ書き換える。翻訳先言語は
//  渡さない（言語を固定すると、原文と異なる言語へ寄せる指示になりやすい）。
//

import Foundation

/// 簡易化用プロンプトの組み立て。
enum SimplifyPrompt {

    /// 簡易化用 system プロンプト。
    ///
    /// 言語コードは渡さない。「同じ言語のまま」と明示し、翻訳へ逃げないようにする。
    /// 出力は簡易化した本文のみ（解説・引用符なし）。翻訳プロンプトと同じく
    /// 1 行連結で、改行を入れない。
    static func systemPrompt() -> String {
        [
            "You simplify the source text so it is easier to understand. ",
            "Keep the same language as the source text — do not translate into another language. ",
            "Prefer shorter sentences, everyday vocabulary, and clear wording, without changing meaning. ",
            "Preserve meaning exactly — do not add, omit, or invent information. ",
            "Respond with the simplified text only. Do not add explanations, notes, or quotation marks. ",
        ].joined()
    }

    /// 簡易化リクエストのメッセージ列を組み立てる。
    ///
    /// - Parameter text: 原文（呼び出し側で前後空白を除去済みであること）。
    static func messages(text: String) -> [GeminiMessage] {
        [
            .init(content: text),
        ]
    }
}
