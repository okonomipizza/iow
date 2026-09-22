//
//  KeychainStoreTests.swift
//  IOWTests
//
//  本番 `KeychainStore.hasPassword` の存在確認経路の検証。
//
//  UI テストは `InMemoryKeychainStore` を使うため、attributes のみの
//  `SecItemCopyMatching` が壊れていても緑のままになる。ここだけ実 Keychain に
//  一時 account を書き、set → hasPassword → get → delete → hasPassword を固定する。
//  `kSecReturnData` を付けていないこと自体は Security の差し替え無しでは断言できないが、
//  値を読まずに存在だけ見る契約が実行時に通ることはここで保証する。
//

import Foundation
import Testing
@testable import IOW

struct KeychainStoreTests {

    /// 一時 account で存在確認が set / delete と一致すること。
    @Test func hasPasswordReflectsItemExistenceWithoutRequiringGet() throws {
        // 他テストや手動実験とぶつからないよう、UUID 付きの捨て account を使う。
        let account = "iow.test.hasPassword.\(UUID().uuidString)"
        let store = KeychainStore(account: account)
        defer {
            // 失敗途中でも Keychain に残さない。
            try? store.deletePassword()
        }

        #expect(!store.hasPassword)

        try store.setPassword("ephemeral-test-secret")
        #expect(store.hasPassword)
        // get は別経路。hasPassword が true でも値が読めることを一度だけ確認する。
        #expect(try store.getPassword() == "ephemeral-test-secret")

        try store.deletePassword()
        #expect(!store.hasPassword)
    }
}
