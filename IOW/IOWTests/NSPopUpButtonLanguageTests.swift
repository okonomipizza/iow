//
//  NSPopUpButtonLanguageTests.swift
//  IOWTests
//
//  言語選択ポップアップと `Language` の対応づけの検証。
//
//  ここが崩れると、ユーザーが選んだ言語と実際に翻訳へ渡る言語がずれる。
//  しかも `targetLanguageChanged` は選択を UserDefaults へ書き込むため、
//  ずれた値がそのまま次回起動へ持ち越される。
//

import AppKit
import Testing
@testable import IOW

@Suite("NSPopUpButton + Language")
@MainActor
struct NSPopUpButtonLanguageTests {

    @Test("every selectable language survives a select-then-read round trip")
    func roundTripsEverySelectableLanguage() {
        let popUp = NSPopUpButton()
        popUp.addLanguageItems()

        // 「項目の並び順 = Language.selectable の添字」という前提そのものを固定する。
        // 1 つでもずれていれば、この往復のどこかで別の言語が返る。
        for language in Language.selectable {
            popUp.selectLanguage(language)
            #expect(popUp.selectedLanguage == language)
        }
    }

    @Test("adds one item per selectable language, labelled with its display name")
    func addsOneItemPerSelectableLanguage() {
        let popUp = NSPopUpButton()
        popUp.addLanguageItems()

        #expect(popUp.numberOfItems == Language.selectable.count)
        #expect(popUp.itemTitles == Language.selectable.map(\.displayName))
    }

    @Test("returns nil for a pop-up that has no items")
    func returnsNilWhenThereAreNoItems() {
        // 空のポップアップは項目数の検査で弾かれる（-1 の判定までは進まない）。
        let popUp = NSPopUpButton()

        #expect(popUp.selectedLanguage == nil)
    }

    @Test("returns nil when the language list is present but nothing is selected")
    func returnsNilWhenNothingIsSelected() {
        // 項目数の検査は通ったうえで indexOfSelectedItem が -1 になる経路。
        // 空のポップアップとは別の分岐なので、こちらも固定しておく。
        let popUp = NSPopUpButton()
        popUp.addLanguageItems()
        popUp.selectItem(at: -1)

        #expect(popUp.indexOfSelectedItem == -1)
        #expect(popUp.selectedLanguage == nil)
    }

    @Test("does nothing when the items have not been added yet")
    func ignoresSelectionBeforeItemsAreAdded() {
        // addLanguageItems() より前に呼んでも、存在しない添字を選ぼうとしない。
        let popUp = NSPopUpButton()

        popUp.selectLanguage(.spanish)

        #expect(popUp.indexOfSelectedItem == -1)
    }

    @Test("returns nil when the items are not the language list")
    func returnsNilWhenItemsAreNotTheLanguageList() {
        // 先頭に別の項目を足すと添字が 1 つずれる。ずれたまま添字を解くと
        // それらしい別の言語を返してしまうので、項目数の食い違いで弾く。
        let popUp = NSPopUpButton()
        popUp.addItem(withTitle: "自動検出")
        popUp.addLanguageItems()
        popUp.selectItem(at: 1)

        #expect(popUp.selectedLanguage == nil)
    }

    @Test("keeps the current selection when the language is not selectable")
    func ignoresLanguagesOutsideTheSelectableList() {
        let popUp = NSPopUpButton()
        popUp.addLanguageItems()
        popUp.selectLanguage(.japanese)

        popUp.selectLanguage(Language(code: "xx", displayName: "未対応"))

        #expect(popUp.selectedLanguage == .japanese)
    }
}
