//
//  AppConfig.swift
//  IOW
//
//  ユーザーが変えられる設定をまとめた値型。
//
//  永続化は `AppConfigStore`。ここは形とデフォルト、および UI / event-tap 向けの
//  表示・照合ヘルパーだけを持つ。`AppConfig()` が現行ハードコードと同じ意味に
//  なることが、未設定時のフォールバックの前提である。
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// キーボードショートカット 1 つ分の割り当て。
///
/// 正準は Carbon / `CGEvent` の virtual key code（`keyCode`）。表示用の
/// `displayString` はキーボードレイアウトに依存するため、当面は ANSI 配列を前提にする。
///
/// 修飾キーは AppKit の `NSEvent.ModifierFlags` をそのまま持つ。
///
/// 型名を `KeyboardShortcut` にしないのは、SwiftUI の同名型とモジュール内で
/// 衝突するためである。`Hashable` は付けない（`NSEvent.ModifierFlags` が
/// Hashable でない）。設定の比較・永続化には `Equatable` で足りる。
struct HotkeyBinding: Equatable, Sendable {

    /// Carbon virtual key code（`CGEvent` の `keyboardEventKeycode` と同じ単位）。
    var keyCode: UInt16

    /// 修飾キー。`.command` / `.shift` など、NSButton・CGEvent 双方で使う集合。
    ///
    /// `NSEvent.ModifierFlags` は OptionSet なので Sendable として扱える。
    /// device-dependent なビット（capsLock 等）は設定値には含めない想定。
    var modifiers: NSEvent.ModifierFlags

    /// 選択テキストの翻訳トリガー。既定は ⌘G。
    static let translate = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_G),
        modifiers: .command
    )

    // MARK: - Presentation / matching

    /// 設定画面のショートカット欄とログ向けの表示文字列（例: `⌘⇧A`、`⌘↩`）。
    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += Self.keyDisplayName(for: keyCode)
        return parts
    }

    /// CGEvent の keyCode / 修飾フラグがこの割り当てと一致するか。
    ///
    /// command / shift / option / control だけを比較する。capsLock 等は無視する。
    func matches(keyCode eventKeyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard eventKeyCode == CGKeyCode(keyCode) else { return false }

        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let eventMods = flags.intersection(relevant)

        var expected: CGEventFlags = []
        if modifiers.contains(.command) { expected.insert(.maskCommand) }
        if modifiers.contains(.shift) { expected.insert(.maskShift) }
        if modifiers.contains(.option) { expected.insert(.maskAlternate) }
        if modifiers.contains(.control) { expected.insert(.maskControl) }

        return eventMods == expected
    }

    /// `displayString` 用のキー名。
    nonisolated private static func keyDisplayName(for keyCode: UInt16) -> String {
        // KeypadEnter / ForwardDelete は HotkeyBindingParsing が受理しないためここには来ない。
        switch Int(keyCode) {
        case kVK_Return:
            return "↩"
        case kVK_Space:
            return "Space"
        case kVK_Escape:
            return "Esc"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "⌫"
        default:
            if let ch = ansiLetterOrDigit(for: keyCode) {
                return String(ch).uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    /// A–Z / 0–9 の ANSI key code。該当しなければ `nil`。
    nonisolated private static func ansiLetterOrDigit(for keyCode: UInt16) -> Character? {
        let map: [UInt16: Character] = [
            UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
            UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
            UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
            UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
            UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
            UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
            UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
            UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
            UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
        ]
        return map[keyCode]
    }
}

/// ⌘G で起動するテキスト処理のモード。
///
/// メニューバーから切り替え、UserDefaults に永続化する。
/// Translate は `preferredTargetLanguage` へ翻訳し、Simplify は原文の言語を
/// 変えずにやさしい表現へ書き換える。
enum TextActionMode: String, Equatable, Sendable, CaseIterable {
    /// 選択テキストを `preferredTargetLanguage` へ翻訳する。
    case translate

    /// 選択テキストを、言語を変えずに簡易化する。
    case simplify

    /// メニューバー表示用のラベル。機能名は英語のままにする。
    var menuTitle: String {
        switch self {
        case .translate: return "Translate"
        case .simplify: return "Simplify"
        }
    }
}

/// ユーザー向け設定のまとまり。
///
/// フィールドはすべてデフォルトを持ち、`AppConfig()` が現行のハードコードと
/// 同じ意味になる。永続化前でも呼び出し側が「設定オブジェクト」を渡せるように
/// するためである。
struct AppConfig: Equatable, Sendable {

    /// 選択テキストを翻訳／簡易化ポップアップへ送るショートカット。
    var translateShortcut: HotkeyBinding = .translate

    /// 翻訳の出力先言語。Simplify では使わない。未設定時の既定は日本語。
    var preferredTargetLanguage: Language = .japanese

    /// ⌘G の処理モード。未設定時の既定は翻訳。
    var textActionMode: TextActionMode = .translate
}
