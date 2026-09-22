//
//  main.swift
//  IOW
//
//  アプリのエントリポイント。
//  storyboard を持たない programmatic AppKit 構成のため、`@main` は使わず、
//  ここで NSApplication と AppDelegate を明示的に結び付けて起動する。
//

import Cocoa

// NSApplication / AppDelegate は MainActor に分離されている。
// プログラム起動時のトップレベルコードはメインスレッド上で実行されるため、
// MainActor.assumeIsolated で MainActor 分離として起動処理を行う。
MainActor.assumeIsolated {
    // NSApplication の共有インスタンスを取得する。
    let application = NSApplication.shared

    // AppDelegate を生成し、delegate として登録する。
    // これがないと applicationDidFinishLaunching が呼ばれず、起動処理が始まらない。
    // NSApplication.delegate は弱参照のため、delegate はこのスコープで強参照し続ける
    // （application.run() がここでブロックするため、アプリ稼働中は生存し続ける）。
    let delegate = AppDelegate()
    application.delegate = delegate

    // Dock アイコンを出さず、メニューバー status item で常駐する。
    application.setActivationPolicy(.accessory)

    // イベントループを開始する（アプリ終了までブロックする）。
    application.run()
}
