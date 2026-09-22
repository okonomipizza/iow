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
    /// - Parameters:
    ///   - text: 表示するプレーンテキスト。
    ///   - heightLimit: パネル高さの上限。超過分はスクロールで見る。既定は
    ///     `maxPanelHeight` だが、`preferredHeightLimit` が求めた空きスペース側の
    ///     上限を渡すことで、全文をスクロールなしで読めるよう伸ばせる。
    /// - Returns: パネルサイズ。
    static func measurePanelSize(
        for text: String,
        heightLimit: CGFloat = maxPanelHeight
    ) -> NSSize {
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
        let chromeHeight = contentPadding * 2 + bottomBarHeight
        let maxBodyHeight = max(0, heightLimit - chromeHeight)
        // 内側余白（`bodyContentInset`）分を足さないと、1 行でも高さが足りず
        // 文字の下半分がクリップされる。
        let neededBodyHeight = textHeight + bodyContentInset.height * 2
        let fieldHeight = min(
            max(neededBodyHeight, bodyMinHeight),
            maxBodyHeight
        )
        let width = min(maxPanelWidth, max(minPanelWidth, ceil(bounding.width) + contentPadding * 2))
        let height = chromeHeight + fieldHeight
        return NSSize(width: width, height: height)
    }

    // MARK: - 配置計算

    /// パネル高さの上限を、配置予定側の空きスペースから決める。
    ///
    /// 全文がスクロールなしで読めることを最優先する。ポップアップは既定でカーソルの
    /// 右下に、上端をカーソルから `cursorOffset` だけ下へ離して置かれる
    /// （`preferredOrigin` の反転規則と同条件）。
    ///
    /// 1. 下側（カーソル下〜可視領域下端）に全文が収まる → その全文分の高さ。
    /// 2. 下側に収まらず上側（反転配置）なら全文が収まる → その高さ（あちらは
    ///    `preferredOrigin` が反転する）。
    /// 3. どちらにも収まらない → 空きの多い側まで伸ばし、差分はスクロールで読む。
    ///
    /// 可視領域が得られない環境（テスト・起動直後）では従来どおり `maxPanelHeight`
    /// を返し、ドラッグ移動済みパネルの既定にもなる。
    ///
    /// - Parameters:
    ///   - text: 表示するプレーンテキスト。
    ///   - mouseLocation: パネル配置の基準になるマウス位置。
    ///   - visibleFrame: マウス位置を含むスクリーンの可視領域。
    /// - Returns: `measurePanelSize(for:heightLimit:)` へ渡す高さ上限。
    static func preferredHeightLimit(
        for text: String,
        mouseLocation: NSPoint,
        visibleFrame: NSRect
    ) -> CGFloat {
        let insetFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        guard insetFrame.width > 0, insetFrame.height > 0 else {
            return maxPanelHeight
        }
        // 全文を入れたときの高さ（上限クランプなし）。これを基準に配置側を選ぶ。
        let neededHeight = measurePanelSize(for: text, heightLimit: .greatestFiniteMagnitude).height
        // 下配置の空き。上端はカーソル - cursorOffset。
        let belowAvailable = mouseLocation.y - cursorOffset - insetFrame.minY
        // 上配置（反転）の空き。下端はカーソル + cursorOffset。
        let aboveAvailable = insetFrame.maxY - (mouseLocation.y + cursorOffset)

        if neededHeight <= belowAvailable {
            return neededHeight
        }
        if neededHeight <= aboveAvailable {
            return neededHeight
        }
        // どちらにも収まらない時のみ、空きの多い側まで伸ばして差分をスクロールさせる。
        // 極端に狭い環境でも最低限の本文（`bodyMinHeight` の 2 行分）は確保する。
        return max(belowAvailable, aboveAvailable, bodyMinHeight * 2)
    }

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
