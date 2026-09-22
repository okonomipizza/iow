//
//  HotkeyBindingParsingTests.swift
//  IOWTests
//
//  ショートカット文字列のパースと検証の固定。
//

import AppKit
import Carbon.HIToolbox
import Testing

@testable import IOW

struct HotkeyBindingParsingTests {

    @Test func parsesCompactDisplayStringForDefault() {
        #expect(parsed("⌘G") == .translate)
    }

    @Test func parsesEnglishPlusSeparatedForms() {
        #expect(parsed("Cmd+G") == .translate)
        #expect(parsed("command+shift+g") == HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_G),
            modifiers: [.command, .shift]
        ))
    }

    @Test func rejectsEmptyAndUnrecognized() {
        #expect(parseFailure("") == .empty)
        #expect(parseFailure("   ") == .empty)
        #expect(parseFailure("⌘") == .unrecognized)
        #expect(parseFailure("Cmd+") == .unrecognized)
        #expect(parseFailure("F13") == .unknownKey)
    }

    @Test func rejectsShiftOnlyAndBareKey() {
        #expect(HotkeyBindingParsing.validate(
            HotkeyBinding(keyCode: UInt16(kVK_ANSI_G), modifiers: .shift)
        ) == .missingNonShiftModifier)
        #expect(HotkeyBindingParsing.validate(
            HotkeyBinding(keyCode: UInt16(kVK_ANSI_G), modifiers: [])
        ) == .missingNonShiftModifier)
    }

    /// NSButton の `keyEquivalent` へ写せないキーも受理する。
    ///
    /// 翻訳ショートカットは event-tap が keyCode で直接照合するため、F1 のような
    /// 割り当ても通る。
    @Test func acceptsKeysWithoutButtonKeyEquivalent() {
        let unmapped = HotkeyBinding(keyCode: UInt16(kVK_F1), modifiers: .command)
        #expect(HotkeyBindingParsing.validate(unmapped) == nil)
    }

    @Test func parsesSpecialKeysAcceptedByPlan() {
        #expect(parsed("⌘Space") == HotkeyBinding(keyCode: UInt16(kVK_Space), modifiers: .command))
        #expect(parsed("Cmd+Space") == HotkeyBinding(keyCode: UInt16(kVK_Space), modifiers: .command))
        #expect(parsed("⌘Esc") == HotkeyBinding(keyCode: UInt16(kVK_Escape), modifiers: .command))
        #expect(parsed("Cmd+Escape") == HotkeyBinding(keyCode: UInt16(kVK_Escape), modifiers: .command))
        #expect(parsed("⌘Tab") == HotkeyBinding(keyCode: UInt16(kVK_Tab), modifiers: .command))
        #expect(parsed("Cmd+Tab") == HotkeyBinding(keyCode: UInt16(kVK_Tab), modifiers: .command))
        #expect(parsed("⌘⌫") == HotkeyBinding(keyCode: UInt16(kVK_Delete), modifiers: .command))
        #expect(parsed("Cmd+Delete") == HotkeyBinding(keyCode: UInt16(kVK_Delete), modifiers: .command))

        for binding in [
            HotkeyBinding(keyCode: UInt16(kVK_Space), modifiers: .command),
            HotkeyBinding(keyCode: UInt16(kVK_Escape), modifiers: .command),
            HotkeyBinding(keyCode: UInt16(kVK_Tab), modifiers: .command),
            HotkeyBinding(keyCode: UInt16(kVK_Delete), modifiers: .command),
        ] {
            #expect(parsed(binding.displayString) == binding)
        }
    }

    @Test func rejectsForwardDelete() {
        #expect(parseFailure("⌘⌦") == .unknownKey)
        #expect(parseFailure("Cmd+ForwardDelete") == .unknownKey)
    }

    @Test func applyingReplacesOnlyTheTranslateShortcut() {
        let config = AppConfig()
        guard case .success(let next) = HotkeyBindingParsing.applying(text: "⌘S", to: config) else {
            Issue.record("Cmd+S should be accepted")
            return
        }
        #expect(next.translateShortcut.keyCode == UInt16(kVK_ANSI_S))
        #expect(next.preferredTargetLanguage == config.preferredTargetLanguage)
        #expect(next.textActionMode == config.textActionMode)
    }

    @Test func applyingPropagatesParseFailure() {
        #expect(applyFailure("⇧G", in: AppConfig()) == .missingNonShiftModifier)
        #expect(applyFailure("", in: AppConfig()) == .empty)
    }

    @Test func roundTripDisplayStringThroughParser() {
        #expect(parsed(HotkeyBinding.translate.displayString) == .translate)
    }

    private func parsed(_ text: String) -> HotkeyBinding? {
        if case .success(let value) = HotkeyBindingParsing.parse(text) { return value }
        return nil
    }

    private func parseFailure(_ text: String) -> HotkeyBindingParseFailure? {
        if case .failure(let error) = HotkeyBindingParsing.parse(text) { return error }
        return nil
    }

    private func applyFailure(
        _ text: String,
        in config: AppConfig
    ) -> HotkeyBindingParseFailure? {
        if case .failure(let error) = HotkeyBindingParsing.applying(text: text, to: config) {
            return error
        }
        return nil
    }
}
