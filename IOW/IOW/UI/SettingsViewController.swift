//
//  SettingsViewController.swift
//  IOW
//
//  簡易設定ウィンドウ。Gemini API キー、出力言語、ショートカットを
//  区切り線で分け、スクロール可能な縦スタックで表示する。
//
//  セクションが増えてもウインドウの固定高を 1 つずつ上げなくて済むよう、内容は
//  スクロールビューの中に置く。
//

import Cocoa

/// `isFlipped` を true にするコンテナ。スクロールビューの document view に置き、
/// 縦スタックを上から下へ配置する。
///
/// 縦 `NSStackView` は flipped でない（座標が下から積み上がる）ため、そのまま
/// document view にすると末尾のセクションがクリップビューの先頭に出てしまう。
/// このコンテナで座標系を反転して、上から読める配置にする。
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Gemini API キー、出力言語、ショートカットを扱う設定 UI。
@MainActor
final class SettingsViewController: NSViewController {

    /// キーの保存先。テストはモックを注入する。
    private let keyStore: any KeychainStoring
    private let configStore: AppConfigStore

    /// キー削除時の確認。テストはモーダルを避けるため `{ true }` を渡す。
    private let confirmDelete: @MainActor (String) -> Bool

    /// 内容全体を載せるスクロールビュー。
    private let scrollView = NSScrollView()

    /// 出力先言語選択。
    private let targetPopUp = NSPopUpButton()

    /// ショートカット入力欄（翻訳）。設定できるショートカットはこれだけである。
    private let translateShortcutField = NSTextField()

    /// ショートカットをデフォルトへ戻すボタン。
    private let resetShortcutsButton = NSButton()

    /// ショートカット検証などのフィードバック。
    private let feedbackLabel = NSTextField(labelWithString: "")

    /// - Parameters:
    ///   - keyStore: API キーの保存先。既定は実 Keychain ストアで、テストから
    ///     モックを差し替えられる。
    ///   - configStore: 出力言語・ショートカットなどの設定。既定は UserDefaults。
    ///   - confirmDelete: キー削除の確認。既定はモーダルアラートを表示する。
    init(
        keyStore: any KeychainStoring = KeychainStore(account: APIKeyProvider.geminiAccount),
        configStore: AppConfigStore = AppConfigStore(),
        confirmDelete: @escaping @MainActor (String) -> Bool = APIKeyRowView.defaultDeleteConfirmation
    ) {
        self.keyStore = keyStore
        self.configStore = configStore
        self.confirmDelete = confirmDelete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScrollView()
        configureSubviews()
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // document view の幅をクリップビューに追従させ、高さは中身のスタックが決める。
        // 中身がクリップビューより高ければ縦スクロールになる。
        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])
    }

    private func configureSubviews() {
        let keyTitleLabel = sectionTitle("Gemini API キー")

        let keyDescriptionLabel = NSTextField(
            wrappingLabelWithString: "Gemini の API キーを保存します。キーはこの Mac の Keychain にのみ保存され、Google へは IOW が直接送ります。"
        )
        keyDescriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        keyDescriptionLabel.textColor = .secondaryLabelColor

        // キー行。現状 Gemini の 1 行だけである。
        let keyRow = APIKeyRowView(store: keyStore, confirmDelete: confirmDelete)

        let languageTitleLabel = sectionTitle("出力言語")
        targetPopUp.target = self
        targetPopUp.action = #selector(targetLanguageChanged)

        let shortcutsTitleLabel = sectionTitle("ショートカット")
        let shortcutsDescriptionLabel = NSTextField(
            wrappingLabelWithString: "記号（⇧⌘A）または英語（Cmd+Shift+A）で入力し、Return かフォーカス移動で確定します。翻訳の既定は ⌘G です。発火時は選択範囲を一時的にコピーして取得します。"
        )
        shortcutsDescriptionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        shortcutsDescriptionLabel.textColor = .secondaryLabelColor

        let translateRow = makeShortcutRow(title: "翻訳", field: translateShortcutField)

        resetShortcutsButton.title = "デフォルトに戻す"
        resetShortcutsButton.bezelStyle = .rounded
        resetShortcutsButton.target = self
        resetShortcutsButton.action = #selector(resetShortcutsButtonTapped)

        feedbackLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        feedbackLabel.textColor = .systemRed

        targetPopUp.addLanguageItems()
        let config = configStore.load()
        reloadShortcutFields(from: config)
        targetPopUp.selectLanguage(config.preferredTargetLanguage)

        // セクション間の区切り線。キー → 言語 → ショートカット。
        let keyLanguageSeparator = sectionSeparator()
        let languageShortcutsSeparator = sectionSeparator()

        let stack = NSStackView(
            views: [keyTitleLabel, keyDescriptionLabel, keyRow] + [
                keyLanguageSeparator,
                languageTitleLabel,
                targetPopUp,
                languageShortcutsSeparator,
                shortcutsTitleLabel,
                shortcutsDescriptionLabel,
                translateRow,
                resetShortcutsButton,
                feedbackLabel,
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        // document view は configureScrollView の中で作る。ここでは縦スタックを
        // コンテナに固定し、高さの決定をスタックに委ねる。
        guard let documentView = scrollView.documentView else {
            assertionFailure("scrollView.documentView has not been configured")
            return
        }
        documentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            documentView.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 24),
            // 折り返しラベル・区切り線はスタックの全幅に張る。
            keyDescriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutsDescriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            keyLanguageSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            languageShortcutsSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            translateRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        // キー行も行内の入力欄を伸ばすためスタックの全幅に張る。
        keyRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// セクション見出しを作る。
    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    /// セクション間の区切り線（横線）。幅はスタック側で揃える。
    private func sectionSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// ラベル + テキスト欄の 1 行。
    ///
    /// **行を増やすなら `shortcutFieldCommitted(_:)` を先に直すこと。** あちらは
    /// `sender` を見ずに翻訳ショートカットへ書き込む。役割が 1 つしか無いあいだは
    /// それで足りるが、2 行目を足すとその行の確定が黙って翻訳ショートカットを
    /// 上書きする（コンパイルエラーにも実行時エラーにもならない）。
    private func makeShortcutRow(title: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.setContentHuggingPriority(.required, for: .horizontal)
        // 見出し幅を固定しておく。
        label.widthAnchor.constraint(equalToConstant: 56).isActive = true

        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.placeholderString = "⌘G"
        field.target = self
        field.action = #selector(shortcutFieldCommitted(_:))
        field.cell?.sendsActionOnEndEditing = true

        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    /// ストアの値をショートカット欄へ反映する（正規化表示は `displayString`）。
    private func reloadShortcutFields(from config: AppConfig) {
        translateShortcutField.stringValue = config.translateShortcut.displayString
    }

    /// 出力先言語ポップアップの選択変更を設定ストアに保存する。
    @objc private func targetLanguageChanged() {
        guard let language = targetPopUp.selectedLanguage else {
            return
        }
        var config = configStore.load()
        config.preferredTargetLanguage = language
        configStore.save(config)
    }

    /// ショートカット欄の確定（Return / フォーカス喪失）。
    ///
    /// `sender` は見ない。ショートカット欄が翻訳の 1 つだけだからである
    /// （増やすときの注意は `makeShortcutRow` のコメントにある）。
    @objc private func shortcutFieldCommitted(_ sender: NSTextField) {
        let config = configStore.load()
        switch HotkeyBindingParsing.applying(text: sender.stringValue, to: config) {
        case .success(let next):
            configStore.save(next)
            reloadShortcutFields(from: next)
            feedbackLabel.stringValue = ""
        case .failure(let error):
            reloadShortcutFields(from: config)
            feedbackLabel.textColor = .systemRed
            feedbackLabel.stringValue = Self.feedbackMessage(for: error)
        }
    }

    /// ショートカットを `AppConfig()` のデフォルトへ戻す。
    @objc private func resetShortcutsButtonTapped() {
        var config = configStore.load()
        config.translateShortcut = AppConfig().translateShortcut
        configStore.save(config)
        reloadShortcutFields(from: config)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.stringValue = "ショートカットをデフォルトに戻しました。"
    }

    private static func feedbackMessage(for error: HotkeyBindingParseFailure) -> String {
        switch error {
        case .empty:
            return "ショートカットを入力してください。"
        case .unrecognized:
            return "ショートカットの形式を認識できません。"
        case .missingNonShiftModifier:
            return "⌘ / ⌥ / ⌃ のいずれかを含めてください。"
        case .unknownKey:
            return "キー名を認識できません。"
        }
    }
}
