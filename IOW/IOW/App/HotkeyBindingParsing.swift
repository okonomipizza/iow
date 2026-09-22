//
//  HotkeyBindingParsing.swift
//  IOW
//
//  設定画面でユーザーが打ち込んだショートカット文字列を `HotkeyBinding` へ
//  変換して検証する。UI から切り離してテスト可能にする。
//
//  設定できるショートカットは翻訳（event-tap）の 1 つだけである。
//
//  受け付ける表記:
//    - 記号（`displayString` と同じ）: `⇧⌘A`、`⌘↩`
//    - 英語（`+` 区切り）: `Cmd+Shift+A`、`Command+Return`
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// 文字列からのパース／検証失敗理由。
enum HotkeyBindingParseFailure: Error, Equatable, Sendable {
    /// 空文字、または空白だけ。
    case empty
    /// 修飾キーもキー名も解釈できない。
    case unrecognized
    /// command / option / control が一つも無く、shift だけ（または修飾なし）。
    case missingNonShiftModifier
    /// キー名は読めたが ANSI / 既知特殊キーに落ちない。
    case unknownKey
}

/// ショートカット文字列のパースと、Settings 保存前の検証。
enum HotkeyBindingParsing {

    /// テキストを `HotkeyBinding` へ変換する（役割固有の制約は見ない）。
    ///
    /// - Parameter text: ユーザー入力。前後空白は無視する。
    /// - Returns: 成功時は binding。失敗時は理由。
    static func parse(_ text: String) -> Result<HotkeyBinding, HotkeyBindingParseFailure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        if trimmed.contains("+") {
            return parsePlusSeparated(trimmed)
        }
        return parseCompactSymbols(trimmed)
    }

    /// 修飾キーの最低条件を見る。
    ///
    /// command / option / control のいずれかが要る。shift だけ（や修飾なし）を許すと、
    /// 通常のタイプ入力を event-tap が吞んでしまう。
    static func validate(_ binding: HotkeyBinding) -> HotkeyBindingParseFailure? {
        let relevant = binding.modifiers.intersection([.command, .shift, .option, .control])
        let hasNonShift = relevant.contains(.command)
            || relevant.contains(.option)
            || relevant.contains(.control)
        guard hasNonShift else { return .missingNonShiftModifier }
        return nil
    }

    /// パース → 検証まで一括。成功時は正規化表示用の binding。
    static func acceptedBinding(from text: String) -> Result<HotkeyBinding, HotkeyBindingParseFailure> {
        switch parse(text) {
        case .failure(let error):
            return .failure(error)
        case .success(let binding):
            if let error = validate(binding) {
                return .failure(error)
            }
            return .success(binding)
        }
    }

    /// 成功時は翻訳ショートカットを差し替えた `AppConfig`。失敗時は理由だけ。
    static func applying(text: String, to config: AppConfig) -> Result<AppConfig, HotkeyBindingParseFailure> {
        switch acceptedBinding(from: text) {
        case .failure(let error):
            return .failure(error)
        case .success(let binding):
            var next = config
            next.translateShortcut = binding
            return .success(next)
        }
    }

    // MARK: - Compact symbols (`⇧⌘A`)

    private static func parseCompactSymbols(_ text: String) -> Result<HotkeyBinding, HotkeyBindingParseFailure> {
        var modifiers: NSEvent.ModifierFlags = []
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            switch ch {
            case "⌃":
                modifiers.insert(.control)
                index = text.index(after: index)
            case "⌥":
                modifiers.insert(.option)
                index = text.index(after: index)
            case "⇧":
                modifiers.insert(.shift)
                index = text.index(after: index)
            case "⌘":
                modifiers.insert(.command)
                index = text.index(after: index)
            default:
                let keyName = String(text[index...])
                guard let keyCode = keyCode(forKeyName: keyName) else {
                    return .failure(keyName.isEmpty ? .unrecognized : .unknownKey)
                }
                return .success(HotkeyBinding(keyCode: keyCode, modifiers: modifiers))
            }
        }

        // 修飾だけあってキーが無い。
        return .failure(.unrecognized)
    }

    // MARK: - Plus-separated English (`Cmd+Shift+A`)

    private static func parsePlusSeparated(_ text: String) -> Result<HotkeyBinding, HotkeyBindingParseFailure> {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
            return .failure(.unrecognized)
        }

        var modifiers: NSEvent.ModifierFlags = []
        var keyName: String?

        for part in parts {
            if let flag = modifierFlag(forToken: part) {
                modifiers.insert(flag)
                continue
            }
            // 非修飾のキー名トークンは 1 つだけ（修飾の前後どちらでもよい）。
            guard keyName == nil else { return .failure(.unrecognized) }
            keyName = part
        }

        guard let keyName, let keyCode = keyCode(forKeyName: keyName) else {
            return .failure(keyName == nil ? .unrecognized : .unknownKey)
        }
        return .success(HotkeyBinding(keyCode: keyCode, modifiers: modifiers))
    }

    private static func modifierFlag(forToken token: String) -> NSEvent.ModifierFlags? {
        switch token.lowercased() {
        case "cmd", "command", "⌘":
            return .command
        case "shift", "⇧":
            return .shift
        case "opt", "option", "alt", "⌥":
            return .option
        case "ctrl", "control", "⌃":
            return .control
        default:
            return nil
        }
    }

    /// キー名（`A` / `↩` / `Return` / `Space` など）→ virtual key code。
    private static func keyCode(forKeyName raw: String) -> UInt16? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name.lowercased() {
        case "return", "enter", "↩", "⏎":
            return UInt16(kVK_Return)
        case "space", " ":
            return UInt16(kVK_Space)
        case "esc", "escape":
            return UInt16(kVK_Escape)
        case "tab":
            return UInt16(kVK_Tab)
        case "delete", "backspace", "⌫":
            return UInt16(kVK_Delete)
        default:
            break
        }

        // 1 文字の英数字。
        guard name.count == 1, let ch = name.lowercased().first else {
            return nil
        }
        return ansiKeyCode(for: ch)
    }

    private static func ansiKeyCode(for character: Character) -> UInt16? {
        let map: [Character: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9),
        ]
        return map[character]
    }
}
