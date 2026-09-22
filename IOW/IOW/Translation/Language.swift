//
//  Language.swift
//  IOW
//
//  翻訳の入力・出力で扱う言語を表現する型。
//

import Foundation

/// 翻訳対象となる言語を表す値型。
///
/// `code` は BCP-47 / ISO 639-1 の言語コード（例: `"ja"`, `"en"`）を保持し、
/// 翻訳エンジン（`Translator`）へ渡す識別子として使う。
/// `displayName` は UI 上での表示用ラベル。
///
/// - Note: `Sendable` に準拠させることで、`Translator` の async メソッドを
///   actor 境界を跨いで呼び出す際に安全に受け渡しできるようにする。
struct Language: Hashable, Sendable {
    /// 言語コード（BCP-47 / ISO 639-1）。翻訳エンジンへ渡す識別子。
    let code: String

    /// UI 表示用の言語名。
    let displayName: String
}

extension Language {
    /// 日本語。
    static let japanese = Language(code: "ja", displayName: "日本語")

    /// 英語。
    static let english = Language(code: "en", displayName: "English")

    /// 中国語（簡体字）。
    static let chineseSimplified = Language(code: "zh-CN", displayName: "中文")

    /// 韓国語。
    static let korean = Language(code: "ko", displayName: "한국어")

    /// フランス語。
    static let french = Language(code: "fr", displayName: "français")

    /// ドイツ語。
    static let german = Language(code: "de", displayName: "Deutsch")

    /// スペイン語。
    static let spanish = Language(code: "es", displayName: "español")

    /// UI の言語選択に表示する言語一覧。
    static let selectable: [Language] = [
        .japanese, .english, .chineseSimplified, .korean,
        .french, .german, .spanish,
    ]
}
