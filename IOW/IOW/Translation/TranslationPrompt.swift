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
    ///
    /// 翻訳元の言語は指定しない。原文の言語はエンジンがテキストから判断する。
    ///
    /// - Parameter target: 訳文の言語コード（例: `"ja"`）。
    static func systemPrompt(target: String) -> String {
        // 改行を含まない 1 行の文字列になる。各要素は末尾に空白 1 つを持ち、連結で並ぶ。
        [
            "You are a professional translator. Translate the source text from its original language to \(target). ",
            "Prefer natural, fluent phrasing in the target language over literal word-for-word calques of source-language structure. ",
            "Restructure source syntax (noun phrases, relative clauses, dummy subjects, and similar constructions) ",
            "into idiomatic target-language wording that a native speaker would use, without changing meaning. ",
            "Especially for en → ja, avoid copying English noun-phrase subjects into stiff 「〜は〜です」 patterns when a more natural Japanese phrasing exists; ",
            "for ja → en, prefer idiomatic English over calques of Japanese word order or particles. ",
            "When translating multi-sentence text, preserve discourse coherence across the whole passage: ",
            "keep anaphora, topic continuity, and logical links between sentences. ",
            "Do not translate each sentence in isolation if that breaks the chain of reference or argument; ",
            "when a pronoun or demonstrative would be ambiguous in the target language, ",
            "prefer a natural rephrasing that keeps the referent clear without adding new information. ",
            "Additionally, assess the text's domain and adapt your translation strategy accordingly: ",
            "- Technical/Scientific: preserve precise terminology and keep technical terms consistent. ",
            "- Legal/Formal: maintain formal register and preserve precise legal wording. ",
            "- Medical: use proper medical terminology and be precise about clinical concepts. ",
            "- Literary: preserve stylistic devices, figurative language, and authorial voice. ",
            "- Business/Corporate: maintain professional register suitable for business correspondence. ",
            "- Academic: preserve academic register and precise abstract concepts. ",
            "- News/Journalistic: maintain factual tone and preserve proper nouns and conventions. ",
            "- Casual/Conversational: prefer natural everyday equivalents and a relaxed colloquial tone. ",
            "- General/Neutral: follow the base instructions above. ",
            "Adapt tone, register, and terminology choice to match the detected domain — ",
            "do not add a domain label or explanation to the output. ",
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
