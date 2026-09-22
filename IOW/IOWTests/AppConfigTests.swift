//
//  AppConfigTests.swift
//  IOWTests
//
//  `AppConfig` のデフォルトが現行ハードコードと一致することを固定する。
//

import AppKit
import Carbon.HIToolbox
import Testing

@testable import IOW

struct AppConfigTests {

    @Test func defaultConfigMatchesTranslateShortcutCommandG() {
        let config = AppConfig()
        #expect(config.translateShortcut.keyCode == UInt16(kVK_ANSI_G))
        #expect(config.translateShortcut.modifiers == .command)
        #expect(config.translateShortcut == .translate)
        #expect(config.translateShortcut.displayString == "⌘G")
    }

    @Test func defaultPreferredTargetLanguageIsJapanese() {
        #expect(AppConfig().preferredTargetLanguage == .japanese)
    }

    @Test func defaultTextActionModeIsTranslate() {
        #expect(AppConfig().textActionMode == .translate)
    }

    @Test func memberwiseOverrideLeavesOtherDefaultsIntact() {
        var config = AppConfig()
        config.translateShortcut = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .option]
        )
        #expect(config.preferredTargetLanguage == .japanese)
        #expect(config.textActionMode == .translate)
        #expect(config.translateShortcut.keyCode == UInt16(kVK_ANSI_K))
        #expect(config.translateShortcut.modifiers == [.command, .option])
    }
}
