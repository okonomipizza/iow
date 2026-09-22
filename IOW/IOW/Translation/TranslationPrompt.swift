//
//  TranslationPrompt.swift
//  IOW
//
//  翻訳用プロンプトの構築。
//
//  プロンプトの改訂はアプリの再配布を伴う。訳文の質を直接左右する文言なので、
//  変えるときは意図を持って変えること。
//

import Foundation

/// 翻訳用プロンプトの組み立て。
enum TranslationPrompt {

    /// 翻訳用 system プロンプト。直訳調を避け、翻訳先として自然な構文を選ばせる。
    /// 固有名詞と専門用語は翻訳せず原形を保たせる。
    ///
    /// 翻訳元の言語は指定しない。原文の言語はエンジンがテキストから判断する。
    ///
    /// - Parameter target: 訳文の言語コード（例: `"ja"`）。
    static func systemPrompt(target: String) -> String {
        // 改行を含まない 1 行の文字列になる。各要素は末尾に空白 1 つを持ち、連結で並ぶ。
        [
            "You are a professional translator. Translate the source text from its original language to \(target). ",
            "Prefer natural, fluent phrasing in the target language over literal word-for-word translation. ",
            "Keep proper nouns (names of people, places, organizations, products, titles) and technical terms in their original form — do not force them into the target language. ",
            "Preserve meaning exactly — do not add, omit, or invent information. ",
            "Respond with the translated text only. Do not add explanations, notes, or quotation marks. ",
        ].joined()
    }

    /// 翻訳リクエストのメッセージ列を組み立てる。
    ///
    /// 言語は system プロンプト（`systemPrompt(target:)`）へ渡される。
    ///
    /// - Parameter text: 原文（呼び出し側で前後空白を除去済みであること）。
    static func messages(text: String) -> [GeminiMessage] {
        [
            .init(content: text),
        ]
    }
}
