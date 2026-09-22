//
//  PopupPanelGeometryTests.swift
//  IOWTests
//
//  訳文ポップアップの寸法・配置計算の検証。
//

import AppKit
import Testing
@testable import IOW

struct PopupPanelGeometrySizeTests {

    /// 折り返し幅の基準。パネル幅ではなく本文領域幅（左右 padding を引いた幅）。
    private static var contentWidth: CGFloat {
        PopupPanelGeometry.maxPanelWidth - PopupPanelGeometry.contentPadding * 2
    }

    /// 指定幅で折り返したときの本文高さ。期待値を作るために計測側と同じ条件で測る。
    private static func textHeight(of text: String, wrappingAt width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(bounding.height)
    }

    /// パネルの縦方向の付帯部分（上下 padding + 下部バー）。
    private static var chromeHeight: CGFloat {
        PopupPanelGeometry.contentPadding * 2 + PopupPanelGeometry.bottomBarHeight
    }

    @Test func wrapsAtTheContentWidthNotThePanelWidth() {
        // 実際に踏んだ不具合の再発検出。折り返し幅をパネル幅（420）で見積もると、
        // 実表示（本文領域幅 420 - 12*2 = 396 で折り返す）より行数が少なく出るため
        // 高さが足りず、訳文の末尾がクリップされる。
        //
        // 幅の差は 24pt しかないので、差が行数として現れるまで行を重ねた文章を使う。
        let text = (1...12)
            .map { "line \($0) with enough words to force the text to wrap" }
            .joined(separator: " ")

        let heightAtContentWidth = Self.textHeight(of: text, wrappingAt: Self.contentWidth)
        let heightAtPanelWidth = Self.textHeight(of: text, wrappingAt: PopupPanelGeometry.maxPanelWidth)
        // 前提が崩れているとテストが素通りするので、まず 2 つの幅で結果が違うことを確かめる。
        #expect(heightAtContentWidth > heightAtPanelWidth)
        // 上限クランプに掛かると差が潰れるため、上限内に収まる文章であることも確かめる。
        #expect(heightAtContentWidth + Self.chromeHeight <= PopupPanelGeometry.maxPanelHeight)

        let size = PopupPanelGeometry.measurePanelSize(for: text)

        // 本文領域幅で折り返した高さ + フィールド内側余白が確保されていること。
        // パネル幅で見積もる実装に戻すと、ここが heightAtPanelWidth ベースになって落ちる。
        let expectedFieldHeight = min(
            max(
                heightAtContentWidth + PopupPanelGeometry.bodyContentInset.height * 2,
                PopupPanelGeometry.bodyMinHeight
            ),
            PopupPanelGeometry.maxPanelHeight - Self.chromeHeight
        )
        #expect(size.height == expectedFieldHeight + Self.chromeHeight)
    }

    @Test func singleLineTextReservesFieldContentInset() {
        let text = "短い訳文"
        let textHeight = Self.textHeight(of: text, wrappingAt: Self.contentWidth)
        let size = PopupPanelGeometry.measurePanelSize(for: text)

        let expectedFieldHeight = max(
            textHeight + PopupPanelGeometry.bodyContentInset.height * 2,
            PopupPanelGeometry.bodyMinHeight
        )
        #expect(size.height == expectedFieldHeight + Self.chromeHeight)
    }

    @Test func heightGrowsWithLineCount() {
        let oneLine = PopupPanelGeometry.measurePanelSize(for: "短い訳文")
        let manyLines = PopupPanelGeometry.measurePanelSize(
            for: Array(repeating: "行", count: 5).joined(separator: "\n")
        )

        #expect(manyLines.height > oneLine.height)
    }

    @Test func clampsHeightAtTheMaximum() {
        // 上限を超える分はスクロールで見る。パネルが画面を覆わないための上限。
        let long = String(repeating: "とても長い訳文。", count: 500)
        let size = PopupPanelGeometry.measurePanelSize(for: long)

        #expect(size.height <= PopupPanelGeometry.maxPanelHeight)
        #expect(size.width <= PopupPanelGeometry.maxPanelWidth)
    }

    @Test func keepsAMinimumWidthForShortText() {
        // 1 文字でもパネルが潰れないこと（下部バーのボタンが並ぶ幅が要る）。
        let size = PopupPanelGeometry.measurePanelSize(for: "あ")

        #expect(size.width >= PopupPanelGeometry.minPanelWidth)
    }
}

struct PopupPanelGeometryPlacementTests {

    private static let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private static let panelSize = NSSize(width: 300, height: 200)

    @Test func placesThePanelBelowRightOfTheCursorByDefault() {
        // 画面中央なら反転は起きず、カーソルの右下に出る。
        let mouse = NSPoint(x: 700, y: 500)
        let origin = PopupPanelGeometry.preferredOrigin(
            mouseLocation: mouse,
            panelSize: Self.panelSize,
            visibleFrame: Self.screenFrame
        )

        #expect(origin.x == mouse.x + PopupPanelGeometry.cursorOffset)
        #expect(origin.y == mouse.y - Self.panelSize.height - PopupPanelGeometry.cursorOffset)
    }

    @Test func flipsAboveTheCursorNearTheBottomEdge() {
        // 下に置くと画面外になる位置では上へ反転する。下端で潰れると訳文が読めない。
        let mouse = NSPoint(x: 700, y: 40)
        let origin = PopupPanelGeometry.preferredOrigin(
            mouseLocation: mouse,
            panelSize: Self.panelSize,
            visibleFrame: Self.screenFrame
        )

        #expect(origin.y > mouse.y)
    }

    @Test func flipsLeftOfTheCursorNearTheTrailingEdge() {
        let mouse = NSPoint(x: 1420, y: 500)
        let origin = PopupPanelGeometry.preferredOrigin(
            mouseLocation: mouse,
            panelSize: Self.panelSize,
            visibleFrame: Self.screenFrame
        )

        #expect(origin.x < mouse.x)
    }

    @Test func alwaysKeepsThePanelInsideTheVisibleArea() {
        // 四隅どこにカーソルがあっても、パネル全体が可視領域の内側に収まること。
        let corners = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: 1440, y: 0),
            NSPoint(x: 0, y: 900),
            NSPoint(x: 1440, y: 900),
        ]
        let inset = Self.screenFrame.insetBy(
            dx: PopupPanelGeometry.screenMargin,
            dy: PopupPanelGeometry.screenMargin
        )

        for mouse in corners {
            let origin = PopupPanelGeometry.preferredOrigin(
                mouseLocation: mouse,
                panelSize: Self.panelSize,
                visibleFrame: Self.screenFrame
            )
            #expect(origin.x >= inset.minX)
            #expect(origin.y >= inset.minY)
            #expect(origin.x + Self.panelSize.width <= inset.maxX)
            #expect(origin.y + Self.panelSize.height <= inset.maxY)
        }
    }

    @Test func clampsAnOriginThatFallsOutsideTheVisibleArea() {
        // ドラッグ後のリサイズなど、外から与えられた原点を寄せ戻す経路。
        let origin = PopupPanelGeometry.clampOrigin(
            NSPoint(x: -500, y: 5000),
            panelSize: Self.panelSize,
            visibleFrame: Self.screenFrame
        )
        let inset = Self.screenFrame.insetBy(
            dx: PopupPanelGeometry.screenMargin,
            dy: PopupPanelGeometry.screenMargin
        )

        #expect(origin.x == inset.minX)
        #expect(origin.y == inset.maxY - Self.panelSize.height)
    }

    @Test func leavesAnOriginThatAlreadyFitsUnchanged() {
        let fitting = NSPoint(x: 400, y: 300)
        let origin = PopupPanelGeometry.clampOrigin(
            fitting,
            panelSize: Self.panelSize,
            visibleFrame: Self.screenFrame
        )

        #expect(origin == fitting)
    }
}
