//
//  AppIdentity.swift
//  IOW
//
//  アプリの識別子を、バンドルから読む唯一の窓口。
//
//  実体を決めているのは `Config/Shared.xcconfig` である。
//  Swift 側にリテラルを持たないのは、識別子が 2 か所に散ると片方だけ直す事故が
//  起きるためである。
//
//  したがって `#if DEBUG` はここには無い。構成の違いはビルド設定が表し、
//  コードはその結果を読むだけにする。
//

import Foundation

/// バンドルから読む、ビルドごとの識別子。
enum AppIdentity {

    /// bundle identifier（`com.okonomipizza.IOW`）。
    ///
    /// Keychain の service とログの subsystem に使う。前者にこれを使うのは、
    /// Keychain の ACL がコード署名の designated requirement で照合される以上、
    /// item の名前も同じ単位で分かれているのが自然なためである。
    ///
    /// `nonisolated` を明示するのは、プロジェクトの `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor` のもとで、バックグラウンドの翻訳経路（Keychain の読み出し等）から
    /// 同期に使われることを示すためである。この値は Bundle.main を参照するだけで、
    /// UI やアクター状態に依存しない。
    nonisolated static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier

    // MARK: - 読めなかった場合

    // バンドルの情報が読めないのは通常起こらない（テストホストから読む場合を含めて
    // Info.plist は常にある）。それでも落とさずに値を返すのは、識別子が取れないことを
    // 理由にアプリを起動不能にする価値が無いためである。
    //
    // **ここだけはこのファイルの原則（Swift 側にリテラルを持たない）の例外である。**
    // 読めなかったときに返す値はどこからも導けないので、`Config/Shared.xcconfig` の
    // **写し**を置いている。あちらを変えたらここも直すこと。

    private static let fallbackBundleIdentifier = "com.okonomipizza.IOW"
}
