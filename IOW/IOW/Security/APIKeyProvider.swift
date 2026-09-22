//
//  APIKeyProvider.swift
//  IOW
//
//  API キーの Keychain 保存先（account 名）の定義。
//
//  Keychain の item は service（bundle identifier）+ account で分かれる。account 名が
//  設定画面と API クライアントの間で散らばると、「設定画面では保存できて、翻訳時は
//  読まれない」キーができる。定義をここで 1 か所にまとめる。
//
//  現状エンジンが接続されているのは Gemini だけである。プロバイダが増えるときは、
//  このファイルを case 付きのカタログ（enum + CaseIterable）へ育て直す。
//

import Foundation

/// API キーの Keychain 保存先に関する定義。
enum APIKeyProvider {

    /// Gemini API キーの Keychain account 名。
    ///
    /// `gemini-api-key` は旧実装からの継続名である。既存ユーザーの保存済みキーを
    /// 今も読めるようにするため、変えない。
    nonisolated static let geminiAccount = "gemini-api-key"
}