//
//  SelectionTextPopupPanelController.swift
//  IOW
//
//  ホットキー取得時に、マウスカーソル付近へ最前面の nonactivating パネルで
//  訳文を表示する。パネルは本文と下部バー（コピーボタン）の 2 要素から成る。
//

import Cocoa

/// 選択テキストの翻訳結果をカーソル位置付近に表示するポップアップパネル。
///
/// アプリ側からパネルをキーウィンドウにすることはない（`orderFrontRegardless`）。
/// ただし型は `KeyablePanel` のままで、利用者が本文をクリックすればキーになる
/// （テキスト選択に要る）。閉じる契機は外クリックと `resignKey` の 2 つで、
/// ドラッグ中だけは自動クローズを抑止する。
@MainActor
final class SelectionTextPopupPanelController: NSObject {

    /// 翻訳 API 呼び出し中プレースホルダのベース文言（末尾ドットはアニメーションで付け替える）。
    private static let translatingBase = "翻訳中"

    /// パネルサイズ算出用の最幅プレースホルダ（3 ドット固定で幅の揺れを防ぐ）。
    private static let translatingPlaceholderForLayout = "翻訳中..."

    /// ドットアニメーションの切り替え間隔（秒）。
    private static let translatingDotInterval: TimeInterval = 0.4

    /// 下部バー下端からボタンまでの余白（ポップアップ縁との隙間）。
    private static let bottomBarBottomInset: CGFloat = 6

    /// 下部バーアイコンボタンの辺長。
    private static let bottomBarIconSize: CGFloat = 20

    /// コピー完了フィードバックを表示する時間（秒）。
    private static let copyFeedbackDuration: TimeInterval = 1.2

    /// コピーボタンの通常アイコン（SF Symbol）。
    private static let copyIconName = "doc.on.doc"

    /// コピー完了時に一時表示するアイコン（SF Symbol）。
    private static let copiedIconName = "checkmark"

    /// ホットキー翻訳のエンジン。
    private let translator: any Translator & Simplifier

    /// ショートカット割り当てと出力言語の読み出し元。
    private let configStore: AppConfigStore

    private var panel: NSPanel?
    private var bodyTextView: NSTextView?
    /// 訳文／原文コピー用ボタン。
    private var copyButton: NSButton?

    /// コピー後のアイコンを元へ戻す遅延タスク（連続コピー時は前回分をキャンセルする）。
    private var copyFeedbackResetTask: Task<Void, Never>?
    /// 「翻訳中」ドットアニメーション用タスク。`dismiss` / 訳文到着時にキャンセルする。
    private var translatingAnimationTask: Task<Void, Never>?
    /// ホットキー翻訳ストリーミング中のタスク。`dismiss` / 新しい翻訳開始時にキャンセルする。
    private var translationStreamTask: Task<Void, Never>?

    /// プレースホルダ表示中（訳文未到着）か。コピー無効化とアニメーション制御に使う。
    private var isTranslating = false

    /// 現在の原文。
    private var sourceText: String = ""
    /// 現在の訳文（コピー対象）。
    private var translatedText: String = ""

    /// パネル配置の基準に使うマウス位置。
    private var anchorMouseLocation: NSPoint?
    /// ユーザーがドラッグで移動済みなら、リサイズで位置を戻さない。
    private var hasBeenMovedByUser = false
    /// 背景ドラッグ中は外クリック・resignKey による自動クローズを抑止する。
    private var isDragging = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    /// - Parameters:
    ///   - translator: ホットキー翻訳のエンジン。
    ///   - configStore: 出力言語等の設定。既定は UserDefaults。
    init(
        translator: any Translator & Simplifier,
        configStore: AppConfigStore = AppConfigStore()
    ) {
        self.translator = translator
        self.configStore = configStore
        super.init()
    }

    /// プレースホルダを出したあと、翻訳ストリームを受信して訳文をパネルへ反映する。
    ///
    /// ストリームを待つ Task は保持し、`dismiss()` と新しい翻訳の開始でキャンセルする。
    /// キャンセルしないと、ポップアップを閉じた後も Gemini は生成を続け、
    /// 使われない結果にトークンを払い続ける（`AsyncThrowingStream.cancellable` のコメント
    /// と同じ問題）。BYOK のため、そのトークンはユーザー自身のキーに請求される。
    ///
    /// 古い結果が新しい翻訳の表示を上書きしないよう、キャンセル状態を UI 更新の直前に
    /// 確かめる。キャンセルの伝播を `onTermination` まで確実に届けるため、各 await の
    /// 直後にも確認する。
    ///
    /// - Parameters:
    ///   - text: 翻訳対象の原文。
    ///   - target: 翻訳先言語。
    func startTranslation(text: String, target: Language) {
        cancelTranslationStream()
        self.sourceText = text
        self.translatedText = ""

        presentTranslatingPanel()

        translationStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            do {
                let stream = self.translator.translate(text, to: target)
                var translated = ""
                for try await delta in stream {
                    guard !Task.isCancelled else { return }
                    translated += delta
                }
                guard !Task.isCancelled else { return }
                self.update(text: translated)
            } catch {
                guard !Task.isCancelled else { return }
                self.update(text: TranslationError.userMessage(for: error))
            }
        }
    }

    /// プレースホルダを出したあと、簡易化ストリームを受信して結果をパネルへ反映する。
    ///
    /// 原文の言語を変えずに書き換えるため、翻訳先言語は指定しない。
    ///
    /// - Parameter text: 簡易化対象の原文。
    func startSimplify(text: String) {
        cancelTranslationStream()
        self.sourceText = text
        self.translatedText = ""

        presentTranslatingPanel()

        translationStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            do {
                let stream = self.translator.simplify(text)
                var simplified = ""
                for try await delta in stream {
                    guard !Task.isCancelled else { return }
                    simplified += delta
                }
                guard !Task.isCancelled else { return }
                self.update(text: simplified)
            } catch {
                guard !Task.isCancelled else { return }
                self.update(text: TranslationError.userMessage(for: error))
            }
        }
    }

    /// 表示中パネルの本文を差し替え、必要ならサイズを再計算する。
    func update(text: String) {
        guard panel != nil else { return }
        stopTranslatingAnimation()
        isTranslating = false
        translatedText = text
        bodyTextView?.string = text
        updateActionButtonsEnabled()
        resizePanel()
    }

    /// ポップアップを閉じ、イベントモニタを解除する。
    ///
    /// 進行中の翻訳ストリームもここでキャンセルされる。閉じたあとも Gemini に生成を
    /// 続けさせないためで、これが `dismiss()` の主要な副作用である
    /// （`cancelTranslationStream`）。
    func dismiss() {
        stopTranslatingAnimation()
        cancelTranslationStream()
        removeClickMonitors()
        copyFeedbackResetTask?.cancel()
        copyFeedbackResetTask = nil
        if let panel {
            panel.delegate = nil
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        clearViewReferences()
        anchorMouseLocation = nil
        hasBeenMovedByUser = false
        isTranslating = false
        isDragging = false
        sourceText = ""
        translatedText = ""
    }

    // MARK: - Presentation

    /// 翻訳待ちプレースホルダを表示し、ドットアニメーションを開始する。
    private func presentTranslatingPanel() {
        // `dismiss()` は `sourceText` も消すので、開き直しに要るぶんだけ控えて戻す。
        let preservedSource = sourceText
        dismiss()
        sourceText = preservedSource
        isTranslating = true
        anchorMouseLocation = NSEvent.mouseLocation
        hasBeenMovedByUser = false
        presentPanel(contextText: Self.translatingPlaceholderForLayout)
        startTranslatingAnimation()
    }

    /// 本文と下部バーを持つパネルを表示する。
    private func presentPanel(contextText: String) {
        let mouseLocation = anchorMouseLocation ?? NSEvent.mouseLocation
        let panelSize = PopupPanelGeometry.measurePanelSize(for: contextText)
        let screen = PopupPanelGeometry.screen(containing: mouseLocation) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let origin = PopupPanelGeometry.preferredOrigin(
            mouseLocation: mouseLocation,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        let contentView = makeContentView(panelSize: panelSize, contextText: contextText)
        guard Self.findIdentifiedTextView(in: contentView, id: Self.bodyTextID) != nil else { return }

        let newPanel = makePanel(
            contentView: contentView,
            frame: NSRect(origin: origin, size: panelSize)
        )
        panel = newPanel
        newPanel.orderFrontRegardless()
        installClickMonitors(for: newPanel)
        updateActionButtonsEnabled()
    }

    /// 本文の量に合わせてパネルサイズを更新する。
    private func resizePanel() {
        guard let panel else { return }
        let panelSize = PopupPanelGeometry.measurePanelSize(for: displayedContextText)
        let mouseLocation = anchorMouseLocation ?? panel.frame.origin
        let screen = PopupPanelGeometry.screen(containing: mouseLocation) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let origin = hasBeenMovedByUser
            ? panel.frame.origin
            : PopupPanelGeometry.preferredOrigin(
                mouseLocation: mouseLocation,
                panelSize: panelSize,
                visibleFrame: visibleFrame
            )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.contentView?.setFrameSize(panelSize)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    /// UI に表示中の本文。
    private var displayedContextText: String {
        isTranslating ? (bodyTextView?.string ?? Self.translatingPlaceholderForLayout) : translatedText
    }

    /// ポップアップ用の nonactivating パネルを生成する。
    ///
    /// フォーカスを奪わない設定はここに一本化する。
    private func makePanel(contentView: NSView, frame: NSRect) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        return panel
    }

    /// `identifier` 付き `NSTextView` を取得する。
    private static func findIdentifiedTextView(
        in root: NSView,
        id: NSUserInterfaceItemIdentifier
    ) -> NSTextView? {
        if let textView = root as? NSTextView, textView.identifier == id {
            return textView
        }
        for subview in root.subviews {
            if let found = findIdentifiedTextView(in: subview, id: id) {
                return found
            }
        }
        return nil
    }

    private static let bodyTextID = NSUserInterfaceItemIdentifier("iow.popup.body")

    // MARK: - Event monitors

    /// パネル外クリックを検知する global / local モニタを登録する。
    private func installClickMonitors(for panel: NSPanel) {
        removeClickMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleOutsideClick(relativeTo: panel)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleOutsideClick(relativeTo: panel)
            }
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    /// クリック位置がパネル外なら閉じる（ドラッグ中は無視）。
    private func handleOutsideClick(relativeTo panel: NSPanel) {
        guard self.panel === panel, !isDragging else { return }
        let clickLocation = NSEvent.mouseLocation
        if !panel.frame.contains(clickLocation) {
            dismiss()
        }
    }

    // MARK: - Layout helpers

    /// 本文 ＋ 下部バーを持つ content view を構築する。
    private func makeContentView(panelSize: NSSize, contextText: String) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: panelSize))
        root.autoresizingMask = [.width, .height]

        let effect = makeEffectView(bounds: root.bounds)
        root.addSubview(effect)

        let body = makeScrollableTextView(string: contextText, identifier: Self.bodyTextID)

        let dragOverlay = makeDragOverlay()
        for view in [body, dragOverlay] {
            root.addSubview(view)
        }
        addBottomBarButtons(to: root)

        // 本文の余白は 2 段になる。パネルの縁からの `contentPadding` と、その内側の
        // `bodyContentInset` である。分けてあるのは `measurePanelSize` が後者だけを
        // 「本文欄の高さ」に数えるためで、片方だけ変えると算出した高さと実表示がずれる。
        let inset = PopupPanelGeometry.bodyContentInset
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: PopupPanelGeometry.contentPadding + inset.height
            ),
            body.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: PopupPanelGeometry.contentPadding + inset.width
            ),
            body.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -(PopupPanelGeometry.contentPadding + inset.width)
            ),
            body.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -(PopupPanelGeometry.bottomBarHeight + PopupPanelGeometry.contentPadding + inset.height)
            ),

            dragOverlay.topAnchor.constraint(equalTo: root.topAnchor),
            dragOverlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dragOverlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dragOverlay.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        activateBottomBarConstraints(in: root)

        bodyTextView = Self.findIdentifiedTextView(in: root, id: Self.bodyTextID)
        return root
    }

    private func makeEffectView(bounds: NSRect) -> NSVisualEffectView {
        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        return effect
    }

    /// 本文用のスクロール可能なテキストビューを作る。
    ///
    /// **枠や背景をこのスクロールビューの layer へ直接設定してはいけない。**
    /// `NSScrollView` / `NSClipView` は backing layer の `backgroundColor` /
    /// `borderColor` / `borderWidth` を `drawsBackground` と `borderType` から毎回
    /// 書き戻すため、設定してもレイアウトのたびに消える。しかも `cornerRadius` と
    /// `masksToBounds` は書き戻さないので、「角丸だけ効いていて枠が無い」という
    /// 気付きにくい壊れ方をする。過去に 2 度これを踏んでいる。描くなら layer を
    /// AppKit が管理しない素の `NSView` を親に置くこと。
    private func makeScrollableTextView(
        string: String,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.identifier = identifier
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainer?.widthTracksTextView = true
        // 既定の lineFragmentPadding(5pt) を残すと折り返し幅が計測幅より左右 5pt ずつ
        // 狭くなり、measurePanelSize が算出する高さが実表示より低くなって本文が
        // クリップされる。折り返し幅を計測幅（スクロールビュー幅）と一致させるため 0 にする。
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = string
        scrollView.documentView = textView
        return scrollView
    }

    private func makeDragOverlay() -> PanelDragOverlayView {
        let dragOverlay = PanelDragOverlayView(
            contentPadding: PopupPanelGeometry.contentPadding,
            bottomBarHeight: PopupPanelGeometry.bottomBarHeight,
            bottomBarBottomInset: Self.bottomBarBottomInset,
            bottomBarIconSize: Self.bottomBarIconSize
        )
        dragOverlay.translatesAutoresizingMaskIntoConstraints = false
        wireDragCallbacks(to: dragOverlay)
        return dragOverlay
    }

    /// 下部バーのコピーボタンを root に追加する。
    private func addBottomBarButtons(to root: NSView) {
        let copyButton = makeIconButton(
            symbolName: Self.copyIconName,
            accessibilityDescription: "Copy",
            toolTip: "Copy to clipboard",
            action: #selector(copyButtonTapped)
        )
        root.addSubview(copyButton)
        self.copyButton = copyButton
        updateActionButtonsEnabled()
    }

    private func makeIconButton(
        symbolName: String,
        accessibilityDescription: String,
        toolTip: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = toolTip
        button.target = self
        button.action = action
        return button
    }

    /// 下部バーボタンの制約を有効化する。
    private func activateBottomBarConstraints(in root: NSView) {
        guard let copyButton else { return }

        NSLayoutConstraint.activate([
            copyButton.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -Self.bottomBarBottomInset
            ),
            copyButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            copyButton.widthAnchor.constraint(equalToConstant: Self.bottomBarIconSize),
            copyButton.heightAnchor.constraint(equalToConstant: Self.bottomBarIconSize),
        ])
    }

    /// ドラッグ overlay へ `isDragging` 制御コールバックを接続する。
    private func wireDragCallbacks(to view: PanelDragOverlayView) {
        view.onDragWillBegin = { [weak self] in
            self?.isDragging = true
        }
        view.onDragDidEnd = { [weak self] in
            self?.isDragging = false
            self?.hasBeenMovedByUser = true
        }
    }

    private func clearViewReferences() {
        bodyTextView = nil
        copyButton = nil
    }

    /// ホットキー翻訳ストリームを畳む。`dismiss` / 新しい翻訳開始時に呼ぶ。
    private func cancelTranslationStream() {
        translationStreamTask?.cancel()
        translationStreamTask = nil
    }

    // MARK: - Translating animation

    /// 「翻訳中」→「翻訳中.」→「翻訳中..」→「翻訳中...」をループ表示する。
    private func startTranslatingAnimation() {
        stopTranslatingAnimation()
        translatingAnimationTask = Task { @MainActor [weak self] in
            var dotCount = 0
            while !Task.isCancelled {
                guard let self, self.isTranslating, let bodyTextView = self.bodyTextView else { return }
                let dots = String(repeating: ".", count: dotCount)
                bodyTextView.string = Self.translatingBase + dots
                dotCount = dotCount >= 3 ? 0 : dotCount + 1
                try? await Task.sleep(nanoseconds: UInt64(Self.translatingDotInterval * 1_000_000_000))
            }
        }
    }

    /// ドットアニメーションを止め、Task を解放する。
    private func stopTranslatingAnimation() {
        translatingAnimationTask?.cancel()
        translatingAnimationTask = nil
    }

    // MARK: - Actions

    /// コピーボタン押下時。表示中の本文をコピーする。
    @objc private func copyButtonTapped() {
        guard isCopyEnabled, let text = copyPayload else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showCopyFeedback()
    }

    /// クリップボードへ載せる文字列。
    private var copyPayload: String? {
        let context = displayedContextText.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? nil : context
    }

    /// テスト専用: 表示中パネルの content view（本番 UI からは使わない）。
    ///
    /// 本文の余白が `measurePanelSize` の前提と一致することを `PopupBodyInsetTests` が
    /// ここから確かめる。
    var panelContentViewForTesting: NSView? { panel?.contentView }

    /// コピー可能か。
    var isCopyEnabled: Bool {
        !isTranslating && copyPayload != nil
    }

    private func updateActionButtonsEnabled() {
        copyButton?.isEnabled = isCopyEnabled
    }

    /// コピー完了をアイコンの一時変更で知らせる。
    private func showCopyFeedback() {
        copyFeedbackResetTask?.cancel()
        copyButton?.image = NSImage(systemSymbolName: Self.copiedIconName, accessibilityDescription: "コピー完了")
        copyButton?.contentTintColor = .systemGreen

        copyFeedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.copyFeedbackDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.copyButton?.image = NSImage(systemSymbolName: Self.copyIconName, accessibilityDescription: "コピー")
            self.copyButton?.contentTintColor = .secondaryLabelColor
        }
    }
}

// MARK: - NSWindowDelegate

extension SelectionTextPopupPanelController: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        // ドラッグ中は自動クローズしない。
        guard !isDragging else { return }
        dismiss()
    }
}
