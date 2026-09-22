//
//  KeychainStore.swift
//  IOW
//
//  macOS Keychain（kSecClassGenericPassword）への読み書きを行う薄いラッパー。
//  API キー等の機密情報を平文ファイルに保存せず、Security framework 経由で保持する。
//

import Foundation
import Security

/// Keychain 操作で発生し得るエラー。
///
/// `Equatable` が必要なのは、テストの `#expect(throws:)` がエラー型の一致を
/// 値比較で判定するためである（swift-testing の制約）。
enum KeychainStoreError: Error, Sendable, Equatable {
    /// 指定 account の項目が存在しない。
    case itemNotFound

    /// 取得した Data が UTF-8 文字列として解釈できない。
    case invalidData

    /// Security framework が想定外の OSStatus を返した。
    case unexpectedStatus(OSStatus)
}

/// `kSecClassGenericPassword` 1 件分の get / set / delete を提供する。
///
/// アクセス制御について（`kSecAttrAccess` を指定していない理由）:
///
/// macOS の file keychain は `SecItemAdd` の時点で「呼び出しアプリのみを信頼する ACL」を
/// 既定で作る。したがって同一ユーザー権限で動く別プロセスは、prompt なしでは値を読めない。
/// 実機（macOS 25.5 / login keychain / ad-hoc 署名のバイナリ 2 本）で確認した結果は次のとおり。
///
///   - 作成したバイナリ自身が読む: `errSecSuccess`（0）
///   - 別バイナリが読む（`SecKeychainSetUserInteractionAllowed(false)` で UI を禁止）:
///     `errSecAuthFailed`（-25293）
///   - 別バイナリが削除する: `errSecInvalidOwnerEdit`（-25244）
///
/// このため `SecAccessCreate` + `SecTrustedApplicationCreateFromPath` で ACL を組み立てる
/// 必要はない（どちらも macOS 10.10 で deprecated であり、既定の保護を再実装するだけになる）。
///
/// ACL の照合は署名の designated requirement で行われる。つまり保護の前提は
/// 「署名したバイナリのコード識別子になりすませないこと」であり、その担保は Release ビルドの
/// Hardened Runtime（library validation とデバッガアタッチの拒否）が受け持つ。
///
/// 機密文字列の保存・読み出し・削除の抽象。
///
/// 実装は `KeychainStore` だけだが、設定画面のテストが Keychain を触らずに
/// 保存・削除・未設定の状態遷移を検証できるよう、protocol として切り出してある。
/// `Translator` 実装から actor 境界を跨いで渡すため `Sendable`。
protocol KeychainStoring: Sendable {
    /// Keychain 項目が存在するかどうか。
    ///
    /// 値そのものは読み出さない。値不要な経路（設定 UI の refresh など）は
    /// `getPassword()` ではなくこちらを使う。
    nonisolated var hasPassword: Bool { get }

    /// 保存済みの値を読み出す。未設定なら `KeychainStoreError.itemNotFound`。
    nonisolated func getPassword() throws -> String

    /// 値を保存する（既存項目があれば上書き）。
    nonisolated func setPassword(_ password: String) throws

    /// 値を削除する。
    nonisolated func deletePassword() throws
}

/// - Note: `Sendable` に準拠させ、`Translator` 実装から actor 境界を跨いで渡せるようにする。
///   `nonisolated` を明示するのは、プロジェクトの `SWIFT_DEFAULT_ACTOR_ISOLATION =
///   MainActor` のもとで、この値型がバックグラウンドの翻訳経路から同期に使われる
/// ことを示すためである。
struct KeychainStore: KeychainStoring, Sendable {

    /// Keychain の service 属性（アプリ単位の名前空間）。
    nonisolated let service: String

    /// Keychain の account 属性（同一 service 内の識別子）。
    nonisolated let account: String

    /// - Parameters:
    ///   - service: Keychain service。既定は本アプリの bundle identifier。
    ///     アプリごとに違う値になるため、他アプリと item を奪い合わない。
    nonisolated init(service: String = AppIdentity.bundleIdentifier, account: String) {
        self.service = service
        self.account = account
    }

    /// Keychain 項目が存在するかどうか。
    ///
    /// 存在確認のみ行い、値そのものはメモリに載せない。
    /// `getPassword()` は使わず、`kSecReturnAttributes` だけで `SecItemCopyMatching`
    /// する（`kSecReturnData` を付けない）。設定 UI の refresh など、値を必要としない
    /// 経路が秘密全文をプロセスへ載せないためである。
    /// UTF-8 としての解釈可否は見ない（それは `getPassword()` の責務）。
    nonisolated var hasPassword: Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    /// Keychain からパスワード文字列を読み出す。
    nonisolated func getPassword() throws -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return password
    }

    /// パスワード文字列を Keychain に保存する（既存項目があれば上書き）。
    nonisolated func setPassword(_ password: String) throws {
        let data = Data(password.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            // 端末ロック中は Keychain から読み出せないようにする（一般的な macOS アプリの既定）。
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    /// Keychain から当該 account の項目を削除する。
    nonisolated func deletePassword() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    /// `SecItemCopyMatching` / `SecItemAdd` 等に渡す共通クエリ。
    nonisolated private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
