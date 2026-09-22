//
//  KeyablePanel.swift
//  IOW
//
//  訳文ポップアップに使う、borderless でもキーウィンドウになれる NSPanel。
//
//  キーになれる必要があるのは、本文の `NSTextView` でテキストを選択するためである
//  （first responder はキーウィンドウにしか置けない）。アプリ側からキーにすることは
//  なく、利用者がパネルを直接クリックしたときだけキーになる。
//

import Cocoa

/// borderless でもキーウィンドウになれるパネル。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
