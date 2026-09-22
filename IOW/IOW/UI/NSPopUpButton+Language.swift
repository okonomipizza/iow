//
//  NSPopUpButton+Language.swift
//  IOW
//
//  言語選択ポップアップの、項目登録・選択・読み出し。
//

import Cocoa

/// `Language.selectable` を並べたポップアップと `Language` の対応づけ。
///
/// 設定ウィンドウの言語ポップアップが「項目の並び順 = `Language.selectable` の添字」
/// という前提を持つ。前提が散らばると、選択肢の作り方を変えたときに片方だけが
/// 古い添字のまま残るため、項目を並べる側（`addLanguageItems()`）と添字を解く側
/// （`selectedLanguage` / `selectLanguage(_:)`）をここへ揃えて、
/// 前提を作る場所と使う場所を同じファイルに置く。
///
/// `NSPopUpButton` のサブクラスにして前提を型で縛る手もあるが、そうすると
/// 言語ポップアップだけ別の型になり、ビューの組み立て箇所が書き換わる。
/// 代わりに `selectedLanguage` が項目数を確かめ、前提が破れていれば `nil` を返す
/// （黙って隣の言語を返さない）。
extension NSPopUpButton {

    /// `Language.selectable` を順に項目として並べる。
    ///
    /// 以後 `selectedLanguage` / `selectLanguage(_:)` が使えるようになる。
    /// 既に項目があるポップアップへ足すと添字がずれるため、空の状態で呼ぶこと。
    func addLanguageItems() {
        for language in Language.selectable {
            addItem(withTitle: language.displayName)
        }
    }

    /// 現在選択されている言語。選択が無い場合と、項目数が `Language.selectable` と
    /// 食い違う場合は `nil`。
    ///
    /// - Note: 見るのは**項目数だけ**で、項目の中身は検査しない。偶然同じ件数を持つ
    ///   無関係なポップアップは弾けないが、狙いは「言語一覧に項目を足し引きしたのに
    ///   添字を解く側が古いまま」を検知することであり、それは件数に現れる。
    var selectedLanguage: Language? {
        // この extension はアプリ内の全 `NSPopUpButton` に生えるので、言語一覧で
        // 埋めていないポップアップにも呼べてしまう。添字だけを見ていると、先頭に
        // セパレータを 1 つ足しただけで全体が 1 つずれ、それらしい
        // 別の言語を黙って返す。
        guard numberOfItems == Language.selectable.count else { return nil }

        // 未選択（項目はあるが選択が無い）のときは -1 になる。
        let index = indexOfSelectedItem
        guard index >= 0 else { return nil }
        return Language.selectable[index]
    }

    /// 指定した言語を選択状態にする。`Language.selectable` に無い言語なら何もしない。
    ///
    /// - Important: `addLanguageItems()` の**後**に呼ぶこと。項目が並ぶ前に呼ぶと
    ///   選択すべき添字が存在しない。順序を取り違えても黙って別の項目を選ばないよう、
    ///   `selectedLanguage` と同じく前提が破れていれば何もしない。
    func selectLanguage(_ language: Language) {
        guard let index = Language.selectable.firstIndex(of: language),
              index < numberOfItems else { return }
        selectItem(at: index)
    }
}
