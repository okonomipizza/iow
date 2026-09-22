//
//  SelectionTextCapture.swift
//  IOW
//
//  前面アプリの選択テキストを、合成 Cmd+C とクリップボード経由で取る。
//  翻訳ホットキー発火時に使い、取得後は可能な範囲でペーストボードを復元する。
//

import AppKit
import Carbon.HIToolbox

/// ペーストボード 1 状態分のスナップショット。
///
/// アイテムごとの型→Data を保持し、`restore` で書き戻す。完全な復元は保証しない
/// （アプリ独自の型や遅延提供データは落ち得る）が、通常の文字列コピーは戻せる。
struct PasteboardSnapshot: Sendable {
    private let items: [[String: Data]]

    /// 現在の一般ペーストボードからスナップショットを取る。
    @MainActor
    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        var archived: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            if !dict.isEmpty {
                archived.append(dict)
            }
        }
        return PasteboardSnapshot(items: archived)
    }

    /// スナップショットをペーストボードへ書き戻す。
    ///
    /// - Returns: 書き戻しに成功したとき `true`。失敗時はクリア後の空に近い状態のまま。
    @MainActor
    @discardableResult
    func restore(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }

        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (rawType, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        let ok = pasteboard.writeObjects(restored)
        return ok
    }
}

/// 合成 Cmd+C による選択テキスト取得。
enum SelectionTextCapture {

    /// コピー完了を待つ上限。
    private static let copyWaitLimit: Duration = .milliseconds(500)

    /// ポーリング間隔。
    private static let copyPollInterval: Duration = .milliseconds(10)

    /// 前面アプリへ Cmd+C を送り、増えたクリップボード文字列を返す。
    ///
    /// 取得の成否にかかわらず、開始前のペーストボード内容の復元を試みる。
    /// - Returns: 非空の文字列。コピーが起きなかった／空なら `nil`。
    @MainActor
    static func copySelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let changeBefore = pasteboard.changeCount

        postCommandC()

        let deadline = ContinuousClock.now + copyWaitLimit
        while ContinuousClock.now < deadline {
            if pasteboard.changeCount != changeBefore {
                let text = pasteboard.string(forType: .string)
                snapshot.restore(to: pasteboard)
                if let text, !text.isEmpty {
                    return text
                }
                return nil
            }
            try? await Task.sleep(for: copyPollInterval)
        }

        snapshot.restore(to: pasteboard)
        return nil
    }

    /// HID タップへ Cmd+C の keyDown / keyUp を投げる。
    nonisolated static func postCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_C)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
