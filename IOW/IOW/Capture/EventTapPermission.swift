//
//  EventTapPermission.swift
//  IOW
//
//  翻訳ホットキー用 CGEvent タップに必要な TCC 権限の確認・要求。
//  キーイベントの監視には Input Monitoring（ListenEvent）が必要。
//  イベントの改変（トリガーキーを吞む defaultTap）には Accessibility も併用する。
//

import ApplicationServices
import CoreGraphics

/// イベントタップ関連の TCC 権限ヘルパー。
enum EventTapPermission {

    /// Input Monitoring（キー／マウス監視）が許可されているか。
    static var canListenEvents: Bool {
        CGPreflightListenEventAccess()
    }

    /// Accessibility（他アプリ制御・一部のフィルタタップ）が許可されているか。
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    /// Input Monitoring の許可を要求する（未許可ならシステムダイアログが出る）。
    ///
    /// - Returns: 要求時点で許可済み、またはユーザーが許可した場合に `true`。
    @discardableResult
    static func requestListenEventAccess() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return CGRequestListenEventAccess()
    }

    /// Accessibility の許可ダイアログを出す（一覧へアプリを載せるため）。
    @discardableResult
    static func requestAccessibilityAccess(prompt: Bool = true) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
