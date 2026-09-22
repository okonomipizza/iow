//
//  APIKeyRowView.swift
//  IOW
//
//  設定画面の「Gemini API キー」セクションの 1 行を表示するビュー。
//
//  行はキーの登録状態で 2 通りの姿を持つ。
//
//    - 未設定:  プロバイダ名 + セキュアな入力欄 + 「登録」ボタン
//    - 登録済み: プロバイダ名 + ● を 10 個並べたマスク表示 + 「削除」ボタン
//
//  キーの本体は画面に一切表示しない。登録済みの行も入力欄を並べず、
//  「何か設定されている」ことだけを ● で伝える。編集は削除 → 再登録の 2 手で行う。
//

import Cocoa

/// 「Gemini API キー」セクションの 1 行。
@MainActor
final class APIKeyRowView: NSView {

    /// 登録済みキーのマスク表示（● ×10）。
    ///
    /// テスト（`SettingsViewControllerTests`）もこの値を参照する。ドット数は
    /// 「何か設定されている」ことの伝達でしかなく、実キーの長さとは無関係。
    static let maskText = "●●●●●●●●●●"

    /// 行の表示名（「Gemini」）。
    private let rowTitle: String

    /// コントロールの accessibility identifier に使う接尾辞。
    private let identifierSuffix: String

    private let store: any KeychainStoring
    private let confirmDelete: (String) -> Bool

    /// プロバイダ名のラベル。
    private let nameLabel = NSTextField(labelWithString: "")

    /// 入力欄。登録済みのときは ● のマスク表示を入れて編集不可にする。
    ///
    /// 未設定と登録済みで同一のビューを使うため、「● の幅 == 入力欄の幅」は
    /// 構造的に保証される（要素を増やして隠し替える方式だとフレームの一致が
    /// レイアウトに依存する）。
    private let keyField = NSSecureTextField()

    /// 未設定時に表示する登録ボタン（ホバーで青）。
    private let registerButton = HoverColoredButton()

    /// 登録済み時に表示する削除ボタン（ホバーで赤）。
    private let deleteButton = HoverColoredButton()

    /// この行だけのフィードバック（保存・削除の結果）。
    private let feedbackLabel = NSTextField(labelWithString: "")

    /// 既定の削除確認。モーダルアラートを表示する。
    ///
    /// static に切り出す理由は、`init` の既定引数と `SettingsViewController` の
    /// 初期化引数の両方から同じ実装を指すためである。行を生成する側が「確認の
    /// 形式」を選択できるようにし、形式の変更は片方の置き換えで済む。
    /// テストはモーダルを避けるため、この代わりに `{ true }` を渡す。
    static func defaultDeleteConfirmation(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(name) の API キーを削除しますか？"
        alert.informativeText = "この Mac からキーが削除されます。サービス側のキーは失効しません。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// - Parameters:
    ///   - title: 行の表示名。プロバイダが増えたら引数で差し替える。
    ///   - identifierSuffix: コントロールの accessibility identifier に使う
    ///     接尾辞（テストが行の特定に使う公開契約。命名を変えるときは
    ///     `SettingsViewControllerTests` の探索関数と同時に行うこと）。
    ///   - store: キーの保存先。テストからモックを注入できるよう protocol で受ける。
    ///   - confirmDelete: 削除確認。既定はモーダルアラートを表示する。テストは
    ///     モーダルを避けるため `{ true }` を渡す。
    ///     既定実装が MainActor 上の `NSAlert` を呼ぶため、クロージャ型に `@MainActor`
    ///     を付けて MainActor 上での呼び出しを型で保証する。
    init(
        title: String = "Gemini",
        identifierSuffix: String = "gemini",
        store: any KeychainStoring,
        confirmDelete: @escaping @MainActor (String) -> Bool = APIKeyRowView.defaultDeleteConfirmation
    ) {
        self.rowTitle = title
        self.identifierSuffix = identifierSuffix
        self.store = store
        self.confirmDelete = confirmDelete
        super.init(frame: .zero)
        configureSubviews()
        refreshState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        nameLabel.stringValue = rowTitle
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        // ラベルの幅を最低 60pt 確保し、入力欄の開始位置を固定する。
        // Gemini（6 文字）を表示するのに十分な幅。
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        keyField.placeholderString = "API キーを入力"
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.font = .systemFont(ofSize: NSFont.systemFontSize)
        // identifier はテストが行のコントロールを特定する公開契約（画面上の見た目に
        // 影響しない）。命名の変更は SettingsViewControllerTests の探索関数と同時に行う。
        keyField.identifier = NSUserInterfaceItemIdentifier("api-key-field-\(identifierSuffix)")

        registerButton.title = "登録"
        registerButton.bezelStyle = .rounded
        registerButton.translatesAutoresizingMaskIntoConstraints = false
        registerButton.hoverColor = .systemBlue
        registerButton.target = self
        registerButton.action = #selector(registerButtonTapped)
        registerButton.identifier = NSUserInterfaceItemIdentifier("api-key-register-\(identifierSuffix)")

        deleteButton.title = "削除"
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.hoverColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonTapped)
        deleteButton.identifier = NSUserInterfaceItemIdentifier("api-key-delete-\(identifierSuffix)")

        feedbackLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        feedbackLabel.textColor = .systemRed
        feedbackLabel.isHidden = true
        // identifier はテストが行のフィードバックを特定する公開契約（上記の各 identifier と同様）。
        feedbackLabel.identifier = NSUserInterfaceItemIdentifier("api-key-feedback-\(identifierSuffix)")

        // 横の並びは「名前ラベル | 入力欄 | 登録ボタン」で、削除ボタンは登録ボタンと
        // 位置・大きさが一致する（片方を hidden で切り替える）。
        //
        // この行は NSStackView を使わない。スタックの配分は intrinsic size を持たない
        // 素の NSView を伸ばす保証がなく、hidden な arranged subview はレイアウトから
        // 外れてフレームが不定になる。位置・幅の等式だけを縦横に直接張り、どの姿でも
        // 同じ解が出るようにする。
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        addSubview(keyField)
        addSubview(registerButton)
        addSubview(deleteButton)
        addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            // --- 横の並び ---
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: keyField.centerYAnchor),
            keyField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            keyField.trailingAnchor.constraint(equalTo: registerButton.leadingAnchor, constant: -8),
            keyField.topAnchor.constraint(equalTo: topAnchor),
            keyField.bottomAnchor.constraint(equalTo: feedbackLabel.topAnchor, constant: -4),
            registerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            registerButton.centerYAnchor.constraint(equalTo: keyField.centerYAnchor),
            // 入力欄を少なくとも 200pt 保つ（文字入力の体感幅）。
            keyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            // ボタン幅は等式で固定し、一意に決める（「登録」「削除」の 2 文字に十分な幅）。
            registerButton.widthAnchor.constraint(equalToConstant: 56),
            deleteButton.widthAnchor.constraint(equalToConstant: 56),

            // --- 削除ボタンは登録ボタンと位置・大きさが一致する ---
            deleteButton.leadingAnchor.constraint(equalTo: registerButton.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: registerButton.trailingAnchor),
            deleteButton.topAnchor.constraint(equalTo: registerButton.topAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: registerButton.bottomAnchor),

            // --- フィードバックは入力欄の下に置く ---
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            feedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            feedbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Keychain の有無に応じて、入力欄の姿とボタンを切り替える。
    ///
    /// 登録済みの入力欄には ● のマスクを入れて編集・選択を止める。同一のビューを
    /// 使い回すので、マスクの幅は常に入力欄の幅と一致する。
    private func refreshState() {
        let hasKey = store.hasPassword
        keyField.isEditable = !hasKey
        keyField.isSelectable = !hasKey
        if hasKey {
            keyField.stringValue = APIKeyRowView.maskText
        } else {
            keyField.stringValue = ""
        }
        registerButton.isHidden = hasKey
        deleteButton.isHidden = !hasKey
    }

    /// 入力欄のキーを Keychain へ保存する。
    @objc private func registerButtonTapped() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            showFeedback("API キーを入力してください。")
            return
        }

        do {
            try store.setPassword(key)
            // 入力欄は保存後すぐクリアし、画面にキーを残さない。
            keyField.stringValue = ""
            refreshState()
            showFeedback("\(rowTitle) の API キーを保存しました。", isSuccess: true)
        } catch {
            // 失敗時も入力欄をクリアする。キーがメモリ上のフィールドへ滞留し続けるのを
            // 防ぐ。失ったのは入力だけなので、ユーザーは同じ内容を再入力できる。
            keyField.stringValue = ""
            showFeedback("保存に失敗しました。")
        }
    }

    /// 保存済みのキーを削除する。誤操作防止のため確認ダイアログを挟む。
    @objc private func deleteButtonTapped() {
        guard confirmDelete(rowTitle) else { return }

        do {
            try store.deletePassword()
            refreshState()
            showFeedback("\(rowTitle) の API キーを削除しました。", isSuccess: true)
        } catch {
            showFeedback("削除に失敗しました。")
        }
    }

    /// この行のフィードバックラベルに結果を表示する。
    ///
    /// 成功は薄いグレー、失敗は赤で出す。表示したら次回の操作で上書きされるまで残す。
    private func showFeedback(_ message: String, isSuccess: Bool = false) {
        feedbackLabel.stringValue = message
        feedbackLabel.textColor = isSuccess ? .secondaryLabelColor : .systemRed
        feedbackLabel.isHidden = false
    }
}

/// ホバー中だけタイトルの色を変える `NSButton`。
///
/// ボタンの bezel は変えず、文字色だけを切り替える。利用者は API キー行だけなので、
/// 汎用の UI 部品にはせずこのファイルに置く。
final class HoverColoredButton: NSButton {

    /// ホバー中にタイトルへ適用する色。
    var hoverColor: NSColor = .labelColor

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // サイズ変更やビュー階層の移動のたびに呼ばれる。古い領域を必ず捨ててから貼り直す。
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        applyColor(hoverColor)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        applyColor(.labelColor)
    }

    /// タイトル文字色を適用する。
    ///
    /// `attributedTitle` を使うのは、`contentTintColor` が bordered bezel の文字色に
    /// 一律に効く保証が無いためである。以後の `title` 変更は `attributedTitle` が
    /// 優先されるが、このクラスで文字列を変える箇所はホバー処理だけであり、衝突しない。
    private func applyColor(_ color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }
}
