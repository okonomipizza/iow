//
//  AppDelegate.swift
//  IOW
//
//  アプリのエントリポイント。storyboard を使わず、メインメニューを
//  コードで構築する（programmatic AppKit）。
//

import Cocoa

// エントリポイントは `main.swift` に定義する。
// macOS の `@main`（NSApplicationMain）は delegate を storyboard/nib から取得するため、
// storyboard を持たない本アプリでは `@main` を使わず、`main.swift` で明示的に
// NSApplication.delegate を設定する。
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// API キー設定などの設定ウィンドウ。
    private var settingsWindow: NSWindow?

    /// メニューバー常駐用の status item。
    private var statusItem: NSStatusItem?

    /// 翻訳ホットキー発火時に訳文を表示するポップアップ。
    private let selectionTextPopup: SelectionTextPopupPanelController

    /// 翻訳／簡易化エンジン（ホットキーポップアップで使用）。
    private let translator: any Translator & Simplifier

    /// ユーザー設定（言語・ショートカット）。ポップアップ / Settings / event-tap で共有する。
    private let appConfigStore: AppConfigStore

    /// 翻訳ホットキー監視（合成 Cmd+C で選択テキストを取る）。
    private var translateHotkeyMonitor: TranslateHotkeyMonitor?

    /// 権限案内を二重表示しないためのフラグ。
    private var didShowEventTapPermissionGuidance = false

    override init() {
        self.translator = GeminiTranslator()
        let configStore = AppConfigStore()
        self.appConfigStore = configStore
        self.selectionTextPopup = SelectionTextPopupPanelController(
            translator: translator,
            configStore: configStore
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // storyboard を使わないため、メインメニューをコードで構築する。
        // これがないとメニューバーが表示されず、Cmd+Q 等のショートカットも効かない。
        NSApp.mainMenu = makeMainMenu()

        setupStatusItem()

        // 翻訳ホットキー監視を開始する（失敗時は権限案内を出す）。
        startTranslateHotkeyMonitor(showGuidanceOnFailure: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        translateHotkeyMonitor?.stop()
        translateHotkeyMonitor = nil
        selectionTextPopup.dismiss()
    }

    /// システム設定から戻ったあとなど、TCC 状態が更新されていることがある。
    func applicationDidBecomeActive(_ notification: Notification) {
        // 許可直後にタップ作成が通ることがあるため、未起動なら再試行する（案内は出さない）。
        startTranslateHotkeyMonitor(showGuidanceOnFailure: false)
    }

    /// 設定ウィンドウを閉じてもメニューバー常駐を続ける。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// 設定ウィンドウを前面に表示する（メニューバーから呼ぶ）。
    @objc private func openSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let viewController = SettingsViewController(
                configStore: appConfigStore
            )
            let window = NSWindow(contentViewController: viewController)
            window.title = "設定"
            // 固定高のまま内容を足すと画面外に溢れるようになったため、縦スクロールを
            // 受けられる大きさまで伸ばし、リサイズも許可する。
            // 既定サイズは SettingsViewController.loadView の frame（480×400）と揃える。
            window.setContentSize(NSSize(width: 480, height: 400))
            // 最小寸法は、1 行の最小構成（名前ラベル 60 + 入力欄 200 + ボタン 56 + 余白）が
            // 収まる幅と、旧固定高（330）で表示できていた範囲を下回らない高さから選ぶ。
            window.contentMinSize = NSSize(width: 420, height: 340)
            window.styleMask = [.titled, .closable, .resizable]
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Status item

    /// メニューバーに status item と操作メニューを追加する。
    ///
    /// 先頭に Translate / Simplify のモード切替と、出力言語一覧を置く。
    /// チェック状態は `menuNeedsUpdate` で毎回 `AppConfig` から同期する。
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            if let image = NSImage(named: "MenuBarIcon") {
                // テンプレート指定にすると、macOS が形（アルファ）だけを取り出し、
                // メニューバーの明暗に応じて自動で黒／白へ塗り分ける。
                // アセット側でも template-rendering-intent を指定しているが、
                // 読み込み経路によらず確実にするためここでも立てる。
                image.isTemplate = true
                image.accessibilityDescription = "IOW"
                button.image = image
            } else {
                // アセットが読めない場合のフォールバック。
                button.title = "G"
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        for mode in TextActionMode.allCases {
            let modeItem = NSMenuItem(
                title: mode.menuTitle,
                action: #selector(selectTextActionMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            menu.addItem(modeItem)
        }
        menu.addItem(NSMenuItem.separator())

        for language in Language.selectable {
            let languageItem = NSMenuItem(
                title: language.displayName,
                action: #selector(selectTargetLanguage(_:)),
                keyEquivalent: ""
            )
            languageItem.target = self
            languageItem.representedObject = language.code
            menu.addItem(languageItem)
        }
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "設定…",
            action: #selector(openSettingsWindow(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let appName = ProcessInfo.processInfo.processName
        // 終了は `quitApp(_:)` 経由で呼ぶ（自動アイコンを避けるため。詳細は同メソッド）。
        let quitItem = NSMenuItem(
            title: "\(appName) を終了",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
    }

    /// メニューバーから ⌘G のモードを切り替える。
    @objc private func selectTextActionMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = TextActionMode(rawValue: raw) else {
            return
        }
        appConfigStore.saveTextActionMode(mode)
    }

    /// メニューバーから翻訳の出力言語を切り替える。
    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String,
              let language = Language.selectable.first(where: { $0.code == code }) else {
            return
        }
        appConfigStore.savePreferredTargetLanguage(language)
    }

    // MARK: - Translate hotkey monitor

    /// 翻訳ホットキー監視を開始する。既に動作中なら何もしない。
    ///
    /// - Parameter showGuidanceOnFailure: タップ作成に失敗したとき権限案内を出すか。
    private func startTranslateHotkeyMonitor(showGuidanceOnFailure: Bool) {
        if let translateHotkeyMonitor, translateHotkeyMonitor.isRunning {
            return
        }

        let monitor = TranslateHotkeyMonitor(
            onTranslate: { [weak self] text in
                guard let self else { return }
                self.handleTextActionHotkey(text)
            },
            configStore: appConfigStore
        )

        if monitor.start() {
            translateHotkeyMonitor = monitor
            return
        }

        translateHotkeyMonitor = nil

        // CGEventTap は Input Monitoring が本命。未許可なら要求し、設定画面への案内を出す。
        if showGuidanceOnFailure, !didShowEventTapPermissionGuidance {
            didShowEventTapPermissionGuidance = true
            _ = EventTapPermission.requestListenEventAccess()
            // defaultTap 用に Accessibility も一覧へ載せておく（既に ON なら何も起きない）。
            _ = EventTapPermission.requestAccessibilityAccess(prompt: true)
            showEventTapPermissionGuidance()
        }
    }

    /// ⌘G で取得した選択テキストを、現在のモードに応じて翻訳または簡易化する。
    @MainActor
    func handleTextActionHotkey(_ text: String) {
        switch appConfigStore.load().textActionMode {
        case .translate:
            translateAndShowInPopup(text)
        case .simplify:
            selectionTextPopup.startSimplify(text: text)
        }
    }

    /// クリップボードから得た原文を翻訳し、結果をカーソル付近のポップアップへ表示する。
    ///
    /// 翻訳ストリームの受信・キャンセルはポップアップ側が引き受ける。
    /// `dismiss()` と新しい翻訳の開始がタスクを止めるため、ここでは Task を管理しない。
    @MainActor
    func translateAndShowInPopup(_ text: String) {
        let target = appConfigStore.load().preferredTargetLanguage

        selectionTextPopup.startTranslation(
            text: text,
            target: target
        )
    }

    /// イベントタップ用権限（Input Monitoring）の許可を促す案内を表示する。
    private func showEventTapPermissionGuidance() {
        let appPath = Bundle.main.bundlePath
        let alert = NSAlert()
        alert.messageText = "入力監視の許可が必要です"
        alert.informativeText = """
        翻訳ショートカットは「入力監視」（Input Monitoring）が必要です。\
        「アクセシビリティ」が ON でも、入力監視が OFF だと動きません。

        システム設定 > プライバシーとセキュリティ > 入力監視 \
        で、次の IOW をオンにしてください:

        \(appPath)

        Xcode から起動している場合、一覧の別の IOW（古いパス）を \
        ON にしても効きません。許可後は IOW を一度終了して再起動してください。
        """
        alert.addButton(withTitle: "入力監視を開く")
        alert.addButton(withTitle: "後で")
        if alert.runModal() == .alertFirstButtonReturn {
            openInputMonitoringPrivacySettings()
        }
    }

    /// システム設定の入力監視画面を開く。
    private func openInputMonitoringPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Menu

    /// アプリを終了する（メニューバーから呼ぶ）。
    ///
    /// `NSApplication.terminate(_:)` を menu item の action に直接指定すると、
    /// macOS 26 が private symbol `Quit_app` の画像を自動で割り当てる。この画像は
    /// action から導出されるため `image` へ nil を代入しても消えず、アイコンを
    /// 持たない他の項目の中で終了項目だけが浮いてしまう。AppKit が認識しない
    /// セレクタを一段挟むことで、自動割り当て自体を避ける。
    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    /// アプリのメインメニューを構築する。
    ///
    /// 最小構成として「アプリメニュー（Quit を含む）」と「Edit メニュー
    /// （コピー・ペースト等の標準編集操作）」を用意する。
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // --- アプリメニュー ---
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(
            withTitle: "\(appName) を隠す",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "設定…",
            action: #selector(openSettingsWindow(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        // 終了は `quitApp(_:)` 経由で呼ぶ（自動アイコンを避けるため。詳細は同メソッド）。
        let quitItem = NSMenuItem(
            title: "\(appName) を終了",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)

        // --- Edit メニュー（テキスト編集の標準操作） ---
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "編集")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    /// メニューを開く直前に、モードと言語のチェック状態を `AppConfig` と同期する。
    ///
    /// 設定画面からの変更も次回オープン時に反映される。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        let config = appConfigStore.load()
        for item in menu.items {
            if let raw = item.representedObject as? String {
                if let mode = TextActionMode(rawValue: raw) {
                    item.state = mode == config.textActionMode ? .on : .off
                } else if Language.selectable.contains(where: { $0.code == raw }) {
                    item.state = raw == config.preferredTargetLanguage.code ? .on : .off
                }
            }
        }
    }
}
