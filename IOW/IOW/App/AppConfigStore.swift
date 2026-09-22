//
//  AppConfigStore.swift
//  IOW
//
//  `AppConfig` の永続化。UserDefaults への読み書きを薄く包む。
//
//  出力言語は既存キー `targetLanguageCode` をそのまま使う。キーを変えると
//  アップデート後にユーザーの言語選択が消えるためである。ショートカットは
//  新規キーで、未設定なら `AppConfig()` のデフォルトへ落とす。
//

import AppKit
import Foundation

/// `AppConfig` の読み書き。
///
/// Settings と event-tap の両方から使う。テストは `UserDefaults(suiteName:)` を
/// 差し込んだ実装を注入できる。
/// `nonisolated` は、プロジェクトの `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// のもとで、CGEvent コールバックなど MainActor 外から同期に読むため。
///
/// UserDefaults はベストエフォートのため、書き込み失敗を呼び出し側へは伝えない。
/// `@unchecked Sendable` は `UserDefaults` が Sendable でないためで、実体は
/// スレッドセーフな defaults ドメインへのアクセスに限る。
struct AppConfigStore: @unchecked Sendable {

    /// 出力言語コード。公開するのはテストが同じ文字列を参照できるようにするため。
    static let targetLanguageCodeKey = "targetLanguageCode"

    private static let translateKeyCodeKey = "appConfig.translateShortcut.keyCode"
    private static let translateModifiersKey = "appConfig.translateShortcut.modifiers"
    /// ⌘G のモード（`translate` / `simplify`）。未設定なら `.translate`。
    static let textActionModeKey = "appConfig.textActionMode"

    private let defaults: UserDefaults

    /// - Parameter defaults: 既定は `UserDefaults.standard`。テストから
    ///   `UserDefaults(suiteName:)` の独立領域を注入できる。
    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    nonisolated func load() -> AppConfig {
        var config = AppConfig()
        config.preferredTargetLanguage = loadTargetLanguage()
        config.translateShortcut = loadHotkey(
            keyCodeKey: Self.translateKeyCodeKey,
            modifiersKey: Self.translateModifiersKey,
            fallback: .translate
        )
        config.textActionMode = loadTextActionMode()
        return config
    }

    nonisolated func save(_ config: AppConfig) {
        defaults.set(config.preferredTargetLanguage.code, forKey: Self.targetLanguageCodeKey)
        defaults.set(config.textActionMode.rawValue, forKey: Self.textActionModeKey)
        saveHotkey(config.translateShortcut, keyCodeKey: Self.translateKeyCodeKey, modifiersKey: Self.translateModifiersKey)
    }

    /// 出力言語だけを書く。ショートカット用キーは触らない。
    ///
    /// メニューバーや言語だけ変える経路で、デフォルトのショートカットを
    /// defaults に刻印しないため。
    nonisolated func savePreferredTargetLanguage(_ language: Language) {
        defaults.set(language.code, forKey: Self.targetLanguageCodeKey)
    }

    /// テキスト処理モードだけを書く。言語・ショートカットのキーは触らない。
    ///
    /// メニューバーからの切替向け。他フィールドをデフォルトで上書きしないため。
    nonisolated func saveTextActionMode(_ mode: TextActionMode) {
        defaults.set(mode.rawValue, forKey: Self.textActionModeKey)
    }

    // MARK: - Private

    nonisolated private func loadTargetLanguage() -> Language {
        let code = defaults.string(forKey: Self.targetLanguageCodeKey) ?? Language.japanese.code
        return Language.selectable.first { $0.code == code } ?? .japanese
    }

    /// 未知の文字列や欠落は `.translate` へ落とす（壊れた値で起動を止めない）。
    nonisolated private func loadTextActionMode() -> TextActionMode {
        guard let raw = defaults.string(forKey: Self.textActionModeKey) else {
            return .translate
        }
        return TextActionMode(rawValue: raw) ?? .translate
    }

    /// キーが一度も書かれていなければ fallback。書かれていても keyCode が
    /// `UInt16` に収まらない壊れた値なら fallback（CGEvent コールバックから
    /// `load()` されるため、範囲外変換でのトラップを避ける）。
    nonisolated private func loadHotkey(
        keyCodeKey: String,
        modifiersKey: String,
        fallback: HotkeyBinding
    ) -> HotkeyBinding {
        guard defaults.object(forKey: keyCodeKey) != nil else {
            return fallback
        }
        let keyCodeInt = defaults.integer(forKey: keyCodeKey)
        guard let keyCode = UInt16(exactly: keyCodeInt) else {
            return fallback
        }
        // modifiers だけ欠ける／壊れている場合は修飾なしとして読む。
        // rawValue が巨大でも OptionSet はビットとして持つだけでトラップしない。
        let modifiersRaw = UInt(clamping: defaults.integer(forKey: modifiersKey))
        let modifiers = NSEvent.ModifierFlags(rawValue: modifiersRaw)
            .intersection(.deviceIndependentFlagsMask)
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    nonisolated private func saveHotkey(
        _ hotkey: HotkeyBinding,
        keyCodeKey: String,
        modifiersKey: String
    ) {
        defaults.set(Int(hotkey.keyCode), forKey: keyCodeKey)
        let modifiers = hotkey.modifiers.intersection(.deviceIndependentFlagsMask)
        defaults.set(Int(modifiers.rawValue), forKey: modifiersKey)
    }
}
