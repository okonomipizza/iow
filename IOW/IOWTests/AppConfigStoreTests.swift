//
//  AppConfigStoreTests.swift
//  IOWTests
//
//  `AppConfigStore` の読み書きとデフォルトフォールバックの検証。
//

import AppKit
import Carbon.HIToolbox
import Testing

@testable import IOW

struct AppConfigStoreTests {

    private func makeIsolatedStore() -> (AppConfigStore, UserDefaults, () -> Void) {
        let suite = "iow.tests.app-config.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AppConfigStore(defaults: defaults)
        return (store, defaults, {
            defaults.removePersistentDomain(forName: suite)
        })
    }

    @Test func targetLanguageCodeKeyRemainsTheLegacyString() {
        #expect(AppConfigStore.targetLanguageCodeKey == "targetLanguageCode")
    }

    @Test func emptyDefaultsLoadAsAppConfigDefaults() {
        let (store, _, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        let config = store.load()
        #expect(config == AppConfig())
        #expect(config.translateShortcut == .translate)
        #expect(config.preferredTargetLanguage == .japanese)
        #expect(config.textActionMode == .translate)
    }

    @Test func legacyTargetLanguageCodeKeyIsHonored() {
        let suite = "iow.tests.app-config.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Language.english.code, forKey: "targetLanguageCode")
        let legacyStore = AppConfigStore(defaults: defaults)

        let config = legacyStore.load()
        #expect(config.preferredTargetLanguage == .english)
        #expect(config.translateShortcut == .translate)
    }

    @Test func outOfRangeKeyCodeFallsBackToDefaultHotkey() {
        let (store, defaults, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        var config = AppConfig()
        config.translateShortcut = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .option]
        )
        store.save(config)
        #expect(store.load().translateShortcut != .translate)

        defaults.set(1_000_000, forKey: "appConfig.translateShortcut.keyCode")
        #expect(store.load().translateShortcut == .translate)
    }

    @Test func savePreferredTargetLanguageDoesNotTouchShortcutKeys() {
        let (store, defaults, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        var config = AppConfig()
        config.translateShortcut = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .option]
        )
        store.save(config)

        store.savePreferredTargetLanguage(.german)
        let loaded = store.load()
        #expect(loaded.preferredTargetLanguage == .german)
        #expect(loaded.translateShortcut == config.translateShortcut)

        let emptySuite = "iow.tests.app-config.lang-only.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let emptyStore = AppConfigStore(defaults: emptyDefaults)
        emptyStore.savePreferredTargetLanguage(.spanish)
        #expect(emptyDefaults.object(forKey: "appConfig.translateShortcut.keyCode") == nil)
        #expect(emptyStore.load().preferredTargetLanguage == .spanish)
        #expect(emptyStore.load().translateShortcut == .translate)

        #expect(defaults.object(forKey: "appConfig.translateShortcut.keyCode") != nil)
    }

    @Test func savePreferredTargetLanguageRoundTripsEverySelectableLanguage() {
        let (store, _, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        for language in Language.selectable {
            store.savePreferredTargetLanguage(language)
            #expect(store.load().preferredTargetLanguage == language)
        }
    }

    @Test func saveTextActionModeDoesNotTouchOtherKeys() {
        let (store, defaults, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        var config = AppConfig()
        config.preferredTargetLanguage = .french
        config.translateShortcut = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .option]
        )
        store.save(config)

        store.saveTextActionMode(.simplify)
        let loaded = store.load()
        #expect(loaded.textActionMode == .simplify)
        #expect(loaded.preferredTargetLanguage == .french)
        #expect(loaded.translateShortcut == config.translateShortcut)
        #expect(defaults.string(forKey: AppConfigStore.textActionModeKey) == "simplify")
    }

    @Test func unknownTextActionModeFallsBackToTranslate() {
        let (store, defaults, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        defaults.set("not-a-mode", forKey: AppConfigStore.textActionModeKey)
        #expect(store.load().textActionMode == .translate)
    }

    @Test func saveAndLoadRoundTripsAllFields() {
        let (store, _, cleanup) = makeIsolatedStore()
        defer { cleanup() }

        var config = AppConfig()
        config.preferredTargetLanguage = .french
        config.textActionMode = .simplify
        config.translateShortcut = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .shift]
        )
        store.save(config)

        let loaded = store.load()
        #expect(loaded.preferredTargetLanguage == .french)
        #expect(loaded.textActionMode == .simplify)
        #expect(loaded.translateShortcut == config.translateShortcut)
    }

    @Test func defaultHotkeyExposesExpectedDisplayString() {
        #expect(HotkeyBinding.translate.displayString == "⌘G")
    }

    /// 修飾キーは過不足なく一致したときだけ通す。
    ///
    /// ⌘G と ⇧⌘G が別物であることが要る。余分な修飾を無視すると、他アプリの
    /// ショートカットを巻き込んで吞んでしまう。
    @Test func translateHotkeyMatchesCommandGExactly() {
        let flags: CGEventFlags = [.maskCommand]
        #expect(HotkeyBinding.translate.matches(keyCode: CGKeyCode(kVK_ANSI_G), flags: flags))
        #expect(!HotkeyBinding.translate.matches(
            keyCode: CGKeyCode(kVK_ANSI_G),
            flags: [.maskCommand, .maskShift]
        ))
        #expect(!HotkeyBinding.translate.matches(keyCode: CGKeyCode(kVK_ANSI_A), flags: flags))
        #expect(!HotkeyBinding.translate.matches(
            keyCode: CGKeyCode(kVK_ANSI_G),
            flags: [.maskCommand, .maskControl]
        ))
        #expect(!HotkeyBinding.translate.matches(
            keyCode: CGKeyCode(kVK_ANSI_G),
            flags: [.maskCommand, .maskAlternate]
        ))
    }
}
