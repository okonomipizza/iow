//
//  SettingsViewControllerTests.swift
//  IOWTests
//
//  設定画面（API キー保存）の検証。
//
//  実 Keychain には触れない。`KeychainStoring` のモックを注入して、設定画面から
//  API キーが保存される経路と、保存・削除・未設定の状態遷移を検証する。
//

import AppKit
import Foundation
import Testing
@testable import IOW

/// メモリ上で動く `KeychainStoring` のモック。
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {

    private(set) var storage: String?

    var hasPassword: Bool { storage != nil }

    func getPassword() throws -> String {
        guard let storage else {
            throw KeychainStoreError.itemNotFound
        }
        return storage
    }

    func setPassword(_ password: String) throws {
        storage = password
    }

    func deletePassword() throws {
        guard storage != nil else {
            throw KeychainStoreError.itemNotFound
        }
        storage = nil
    }
}

/// API キーの保存先が正しく配線されているかの検証。
struct SettingsKeychainWiringTests {

    @Test func theGeminiKeyAccountMatchesTheHistoricalAccountName() {
        // 設定画面の既定ストアと翻訳時の読み出し元（GeminiAPIClient の既定キー
        // プロバイダ）は同じ account 名（APIKeyProvider.geminiAccount）から作られる。
        // ここが食い違うと「保存しても翻訳に使われないキー」ができる
        // （APIKeyProvider のファイル冒頭コメントを参照）。
        //
        // ここで確認するのは、その account が旧実装からの継続名
        // （gemini-api-key）であること——継続名が変わると保存済みキーが
        // 読めなくなる——と、service の既定が bundle identifier であること
        // （他アプリと Keychain item を混ぜないこと）である。
        let settingsStore = KeychainStore(account: APIKeyProvider.geminiAccount)
        let clientStore = KeychainStore(account: APIKeyProvider.geminiAccount)

        #expect(settingsStore.account == "gemini-api-key")
        #expect(settingsStore.account == clientStore.account)
        #expect(settingsStore.service == AppIdentity.bundleIdentifier)
    }

    @Test func theMaskedDisplayShowsExactlyTenDots() {
        // 本番コードの定数と同じ文字列をコピーするのではなく、独立な期待値で固定する。
        #expect(APIKeyRowView.maskText == String(repeating: "●", count: 10))
    }
}

/// すべての操作が失敗する `KeychainStoring` のモック。
///
/// 保存・削除の失敗経路（入力欄クリア、エラーフィードバック、行の状態が変わらない
/// こと）を検証するために使う。
final class AlwaysFailingKeychainStore: KeychainStoring, @unchecked Sendable {

    var hasPassword: Bool { false }

    func getPassword() throws -> String {
        throw KeychainStoreError.unexpectedStatus(-50)
    }

    func setPassword(_ password: String) throws {
        throw KeychainStoreError.unexpectedStatus(-50)
    }

    func deletePassword() throws {
        throw KeychainStoreError.unexpectedStatus(-50)
    }
}

/// 保存は成功するが削除だけが失敗する `KeychainStoring` のモック。
///
/// 削除失敗経路を検証するため、行を登録済みの姿（削除ボタン表示）で作る。
final class KeychainStoreFailingOnDelete: KeychainStoring, @unchecked Sendable {

    var storage = "stored_key"

    var hasPassword: Bool { true }

    func getPassword() throws -> String { storage }

    func setPassword(_ password: String) throws { storage = password }

    func deletePassword() throws {
        throw KeychainStoreError.unexpectedStatus(-25244)
    }
}

/// 設定画面の UI 経由で API キーが保存されるかの検証。
///
/// テストからは実 Keychain を触らない。代わりに `KeychainStoring` のモックを
/// `keyStore` へ注入し、行のアクセシビリティ identifier で操作対象を特定する。
@MainActor
struct SettingsViewControllerTests {

    /// view 階層から identifier 一致のビューを探す（API キー行の各コントロール用）。
    private static func view(identifier: String, in container: NSView) -> NSView? {
        if container.identifier?.rawValue == identifier {
            return container
        }
        for subview in container.subviews {
            if let found = view(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    @Test func savingAKeyStoresItInTheKeychainStore() throws {
        let geminiStore = InMemoryKeychainStore()
        let store = geminiStore
        let controller = SettingsViewController(
            keyStore: store
        )
        // loadView / viewDidLoad を駆動する。
        _ = controller.view

        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSSecureTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        guard let registerButton = Self.view(identifier: "api-key-register-gemini", in: controller.view) as? NSButton else {
            Issue.record("Register button not found in the settings view")
            return
        }

        field.stringValue = "test_gemini_key"
        registerButton.performClick(nil)

        // 保存されたキーはモックへ入り、入力欄は ● 表示の編集不可に切り替わる。
        // 登録ボタンは消え、削除ボタンが出る。
        #expect(geminiStore.storage == "test_gemini_key")
        #expect(field.stringValue == APIKeyRowView.maskText)
        #expect(!field.isEditable)
        #expect(Self.view(identifier: "api-key-delete-gemini", in: controller.view)?.isHidden == false)
        #expect(Self.view(identifier: "api-key-register-gemini", in: controller.view)?.isHidden == true)
        // 保存成功のフィードバックが行に表示される。
        guard let feedback = Self.view(identifier: "api-key-feedback-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Feedback label not found in the settings view")
            return
        }
        #expect(feedback.isHidden == false)
        #expect(feedback.stringValue == "Gemini の API キーを保存しました。")
    }

    @Test func registeredRowShowsMaskedFieldAndDeleteButton() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setPassword("stored_key")
        let store = keychain
        let controller = SettingsViewController(
            keyStore: store
        )
        _ = controller.view

        // 登録済みなので、入力欄が ● 表示の編集不可になり、削除ボタンが出る。
        // 登録ボタンは隠れる。
        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        guard let deleteButton = Self.view(identifier: "api-key-delete-gemini", in: controller.view) as? NSButton else {
            Issue.record("Delete button not found in the settings view")
            return
        }
        guard let registerButton = Self.view(identifier: "api-key-register-gemini", in: controller.view) else {
            Issue.record("Register button not found in the settings view")
            return
        }

        #expect(!field.isHidden)
        #expect(field.stringValue == APIKeyRowView.maskText)
        #expect(!field.isEditable)
        #expect(!field.isSelectable)
        #expect(!deleteButton.isHidden)
        #expect(registerButton.isHidden)
    }

    @Test func alignedButtonsShareTheSamePosition() throws {
        // 削除ボタンは登録ボタンと位置・大きさが一致する制約で重ねられている。
        // レイアウト済みのフレームで確認する（どちらか一方だけが表示される）。
        let keychain = InMemoryKeychainStore()
        try keychain.setPassword("stored_key")
        let store = keychain
        let controller = SettingsViewController(
            keyStore: store
        )
        _ = controller.view
        controller.view.layoutSubtreeIfNeeded()

        guard let registerButton = Self.view(identifier: "api-key-register-gemini", in: controller.view) as? NSButton else {
            Issue.record("Register button not found in the settings view")
            return
        }
        guard let deleteButton = Self.view(identifier: "api-key-delete-gemini", in: controller.view) as? NSButton else {
            Issue.record("Delete button not found in the settings view")
            return
        }

        #expect(registerButton.frame == deleteButton.frame)
    }

    @Test func deletingAKeyRemovesItFromTheKeychainStore() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setPassword("stored_key")
        let store = keychain
        // モーダルアラートを避けるため、確認は常に許可する。
        let controller = SettingsViewController(
            keyStore: store,
            confirmDelete: { _ in true }
        )
        _ = controller.view

        guard let deleteButton = Self.view(identifier: "api-key-delete-gemini", in: controller.view) as? NSButton else {
            Issue.record("Delete button not found in the settings view")
            return
        }

        deleteButton.performClick(nil)

        // 削除され、行が未登録の姿（編集可能な空の入力欄、登録ボタン表示）へ戻る。
        #expect(keychain.storage == nil)
        #expect(Self.view(identifier: "api-key-delete-gemini", in: controller.view)?.isHidden == true)
        #expect(Self.view(identifier: "api-key-register-gemini", in: controller.view)?.isHidden == false)
        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        #expect(!field.isHidden)
        #expect(field.isEditable)
        #expect(field.stringValue.isEmpty)
        // 削除成功のフィードバックが行に表示される。
        guard let feedback = Self.view(identifier: "api-key-feedback-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Feedback label not found in the settings view")
            return
        }
        #expect(feedback.isHidden == false)
        #expect(feedback.stringValue == "Gemini の API キーを削除しました。")
    }

    @Test func aFailedSaveClearsTheInputAndKeepsTheRowUnregistered() {
        let keychain = AlwaysFailingKeychainStore()
        let store = keychain
        let controller = SettingsViewController(
            keyStore: store
        )
        _ = controller.view

        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSSecureTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        guard let registerButton = Self.view(identifier: "api-key-register-gemini", in: controller.view) as? NSButton else {
            Issue.record("Register button not found in the settings view")
            return
        }

        field.stringValue = "test_gemini_key"
        registerButton.performClick(nil)

        // 失敗しても入力欄はクリアされ、行は未登録の姿（編集可能なまま）に残る。
        // フィードバックに失敗が表示される。
        #expect(field.stringValue.isEmpty)
        #expect(field.isEditable)
        #expect(Self.view(identifier: "api-key-field-gemini", in: controller.view)?.isHidden == false)
        guard let feedback = Self.view(identifier: "api-key-feedback-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Feedback label not found in the settings view")
            return
        }
        #expect(feedback.isHidden == false)
        #expect(feedback.stringValue == "保存に失敗しました。")
    }

    @Test func savingAnEmptyKeyIsRejected() {
        let keychain = InMemoryKeychainStore()
        let store = keychain
        let controller = SettingsViewController(
            keyStore: store
        )
        _ = controller.view

        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSSecureTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        guard let registerButton = Self.view(identifier: "api-key-register-gemini", in: controller.view) as? NSButton else {
            Issue.record("Register button not found in the settings view")
            return
        }

        // 空白のみの入力では保存されず、行は未登録のまま。入力欄はクリアせず
        // ユーザーが打ち直せる状態に残し、フィードバックに入力要求が出る。
        field.stringValue = "   "
        registerButton.performClick(nil)

        #expect(keychain.storage == nil)
        #expect(field.isEditable)
        #expect(field.stringValue == "   ")
        guard let feedback = Self.view(identifier: "api-key-feedback-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Feedback label not found in the settings view")
            return
        }
        #expect(feedback.isHidden == false)
        #expect(feedback.stringValue == "API キーを入力してください。")
    }

    @Test func aFailedDeleteKeepsTheRowRegistered() {
        let keychain = KeychainStoreFailingOnDelete()
        let store = keychain
        let controller = SettingsViewController(
            keyStore: store,
            confirmDelete: { _ in true }
        )
        _ = controller.view

        guard let deleteButton = Self.view(identifier: "api-key-delete-gemini", in: controller.view) as? NSButton else {
            Issue.record("Delete button not found in the settings view")
            return
        }

        deleteButton.performClick(nil)

        // 削除が失敗しても行は登録済みの姿のまま（● 表示・編集不可のまま）で、
        // フィードバックに失敗が表示される。
        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        #expect(field.stringValue == APIKeyRowView.maskText)
        #expect(!field.isEditable)
        #expect(keychain.storage == "stored_key")
        guard let feedback = Self.view(identifier: "api-key-feedback-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Feedback label not found in the settings view")
            return
        }
        #expect(feedback.isHidden == false)
        #expect(feedback.stringValue == "削除に失敗しました。")
    }

    @Test func cancelingDeleteLeavesTheKeyAndTheRowUnchanged() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.setPassword("stored_key")
        let store = keychain
        // ユーザーが確認ダイアログでキャンセルした状態を再現する。
        let controller = SettingsViewController(
            keyStore: store,
            confirmDelete: { _ in false }
        )
        _ = controller.view

        guard let deleteButton = Self.view(identifier: "api-key-delete-gemini", in: controller.view) as? NSButton else {
            Issue.record("Delete button not found in the settings view")
            return
        }

        deleteButton.performClick(nil)

        // キャンセルではキーも行の姿も変わらない。
        #expect(keychain.storage == "stored_key")
        guard let field = Self.view(identifier: "api-key-field-gemini", in: controller.view) as? NSTextField else {
            Issue.record("Gemini key field not found in the settings view")
            return
        }
        #expect(field.stringValue == APIKeyRowView.maskText)
        #expect(Self.view(identifier: "api-key-delete-gemini", in: controller.view)?.isHidden == false)
    }

    @Test func settingsShowsTheGeminiKeyRow() {
        // 設定画面には Gemini のキー行（未設定の姿）が出る。
        let controller = SettingsViewController(
            keyStore: InMemoryKeychainStore()
        )
        _ = controller.view

        #expect(Self.view(identifier: "api-key-field-gemini", in: controller.view) != nil)
        #expect(Self.view(identifier: "api-key-register-gemini", in: controller.view) != nil)
    }
}

/// Keychain 保存の状態遷移（実 Keychain を使わないモックでの検証）。
///
/// - Note: ここが検証するのは `InMemoryKeychainStore` という**モック自体**の振る舞い
///   であり、実 Keychain の `SecItemUpdate` / `SecItemAdd` 経路ではない。実 Keychain は
///   テストホストの署名やユーザーの許可に左右されるため、実装側で手動確認している
///   （プロダクションコードの検証は Keychain 書き込みを伴うため、テストではモック注入が
///   できることの確認に留める）。
struct KeychainStoreTransitionsTests {

    @Test func setReadDeleteRoundTrip() throws {
        let keychain = InMemoryKeychainStore()

        #expect(!keychain.hasPassword)
        #expect(throws: KeychainStoreError.itemNotFound) {
            try keychain.getPassword()
        }

        try keychain.setPassword("test_key")
        #expect(keychain.hasPassword)
        #expect(try keychain.getPassword() == "test_key")

        // 上書きできる（再保存は既存 item の更新になる）。
        try keychain.setPassword("another_key")
        #expect(try keychain.getPassword() == "another_key")

        try keychain.deletePassword()
        #expect(!keychain.hasPassword)
        #expect(throws: KeychainStoreError.itemNotFound) {
            try keychain.deletePassword()
        }
    }
}
