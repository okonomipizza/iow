//
//  PopupPanelGeometry.swift
//  IOW
//
//  訳文ポップアップの寸法と配置の計算。
//

import Cocoa

/// 訳文ポップアップのサイズ・位置を決める計算をまとめた名前空間。
///
/// `SelectionTextPopupPanelController` から切り出してある。パネルの見た目に関わる
/// 数値をここへ集め、計算そのものは AppKit の状態に触れない純関数にしてテストできる
/// ようにするため。
///
/// 寸法定数の定義をこの型 1 つに保つのは、ビュー構築側（コントローラの制約）と
/// サイズ計算側で同じ値を参照し、食い違いを作らないためである。制約側も
/// `PopupPanelGeometry.contentPadding` のようにここを参照すること。
enum PopupPanelGeometry {

    // MARK: - 寸法

    /// パネルの最大幅（これを超える行は折り返す）。
    static let maxPanelWidth: CGFloat = 420

    /// パネルの最大高さ（超過分はスクロール）。
    static let maxPanelHeight: CGFloat = 320

    /// 割り込まない最小幅。
    static let minPanelWidth: CGFloat = 200

    /// パネル内側の余白。
    static let contentPadding: CGFloat = 12

    /// カーソルからパネルまでのオフセット。
    static let cursorOffset: CGFloat = 8

    /// 画面端からの最小マージン。
    static let screenMargin: CGFloat = 8

    /// 下部バー（コピーボタン）の高さ。空きスペースはドラッグ可能。
    static let bottomBarHeight: CGFloat = 28

    // MARK: - 本文

    /// パネルの縁の内側余白から、本文の文字までの距離。
    ///
    /// 本文の制約（`makeContentView`）が内容を寄せる量であり、`measurePanelSize` の
    /// 高さ計算もこれを使う。両者がずれると本文がクリップされる。
    ///
    /// **`NSTextView.textContainerInset` へ渡さないこと。** あちらの余白はスクロール
    /// する内容の一部で、スクロールすると一緒に動く。加えて制約側の余白と二重になり、
    /// `measurePanelSize` の高さ計算ともずれる。
    static let bodyContentInset = NSSize(width: 5, height: 4)

    /// 本文の最小高さ（1 行分）。
    ///
    /// システムフォント 13pt の行高 16pt に、上下の `bodyContentInset`（4pt × 2）を
    /// 足した 24pt。`measurePanelSize` が 1 行のときの下限として使う。これを下回ると
    /// 文字の下半分がクリップされる。
    static let bodyMinHeight: CGFloat = 24

    // MARK: - サイズ計算

    /// 表示テキストに応じたパネルサイズを算出する。
    ///
    /// 折り返し幅は「パネル幅 - 左右 `contentPadding`」で見積もる。本文 textView は
    /// `lineFragmentPadding` を 0 にしてあるため、テキストビューの幅がそのまま
    /// 折り返し幅になる。ここをパネル幅で見積もると実表示より高さが足りず、
    /// 本文の末尾がクリップされる。
    ///
    /// **ただし実表示のスクロールビュー幅はこれより左右 `bodyContentInset.width` ずつ
    /// 狭い**（`makeContentView` が `contentPadding + bodyContentInset.width` で寄せる）。
    /// 計測幅のほうが 10pt 広いぶん、折り返しが 1 行増えて末尾がクリップされうる
    /// （計測幅を狭めるとパネル幅も変わるため、この誤差は据え置いている）。
    ///
    /// 「本文欄の高さ」はテキスト高さに `bodyContentInset` の上下分を足した値である
    /// （レイアウト側の制約と同じ内訳。`bodyContentInset` のコメント参照）。
    ///
    /// - Parameter text: 表示するプレーンテキスト。
    /// - Returns: 高さは `maxPanelHeight` でクランプする（超過分はスクロールで見る）。
    static func measurePanelSize(for text: String) -> NSSize {
        let textWidth = maxPanelWidth - contentPadding * 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let textHeight = ceil(bounding.height)
        let maxBodyHeight = maxPanelHeight - contentPadding * 2 - bottomBarHeight
        // 内側余白（`bodyContentInset`）分を足さないと、1 行でも高さが足りず
        // 文字の下半分がクリップされる。
        let neededBodyHeight = textHeight + bodyContentInset.height * 2
        let fieldHeight = min(
            max(neededBodyHeight, bodyMinHeight),
            maxBodyHeight
        )
        let width = min(maxPanelWidth, max(minPanelWidth, ceil(bounding.width) + contentPadding * 2))
        let height = contentPadding + fieldHeight + contentPadding + bottomBarHeight
        return NSSize(width: width, height: min(height, maxPanelHeight))
    }

    // MARK: - 配置計算

    /// カーソル付近に置きつつ、可視領域内に収まる原点を計算する。
    ///
    /// 既定はカーソルの右下。下端に入りきらなければ上へ、右端に入りきらなければ左へ
    /// 反転させ、最後に可視領域内へクランプする。
    static func preferredOrigin(
        mouseLocation: NSPoint,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let insetFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)

        var originX = mouseLocation.x + cursorOffset
        var originY = mouseLocation.y - panelSize.height - cursorOffset

        if originY < insetFrame.minY {
            originY = mouseLocation.y + cursorOffset
        }

        if originX + panelSize.width > insetFrame.maxX {
            originX = mouseLocation.x - panelSize.width - cursorOffset
        }

        return clampOrigin(
            NSPoint(x: originX, y: originY),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
    }

    /// パネル原点を可視領域内へクランプする。
    static func clampOrigin(
        _ origin: NSPoint,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let insetFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let originX = min(max(origin.x, insetFrame.minX), insetFrame.maxX - panelSize.width)
        let originY = min(max(origin.y, insetFrame.minY), insetFrame.maxY - panelSize.height)
        return NSPoint(x: originX, y: originY)
    }

    /// マウス位置を含むスクリーンを返す（見つからなければ `nil`）。
    ///
    /// `NSScreen.screens` を読むためテストできない。上の計算群を純関数に保つために、
    /// 実環境に触るのはこの関数だけへ寄せてある。
    @MainActor
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
