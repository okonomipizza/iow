//
//  PopupBodyInsetTests.swift
//  IOWTests
//
//  ポップアップの本文が、パネルの縁から想定どおりの量だけ内側へ寄ることの検証。
//

import AppKit
import Testing
@testable import IOW

/// 呼び出されても何も返さないテスト用エンジン（レイアウトだけを見る）。
@MainActor
private final class SilentTranslator: Translator, Simplifier {
    func translate(
        _ text: String,
        to target: Language
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func simplify(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// 本文の余白は `contentPadding + bodyContentInset` である。
///
/// このテストが要るのは、**この等式が `measurePanelSize` の前提でもある**ためである。
/// あちらは「本文欄の高さ = テキスト高さ + `bodyContentInset` の上下分」を足して
/// パネル高を決めており、レイアウト側が違う量で寄せると算出した高さと実表示がずれて
/// 本文の末尾がクリップされる。
@MainActor
struct PopupBodyInsetTests {

    @Test func bodyIsInsetByContentPaddingPlusBodyContentInset() {
        let controller = SelectionTextPopupPanelController(translator: SilentTranslator())
        defer { controller.dismiss() }

        // 翻訳開始は常にエンジンを呼ぶが、結果を待つまでは「翻訳中」プレースホルダ
        // が本文に出る（最短の表示経路）。
        controller.startTranslation(text: "Hello", target: .english)

        guard let root = controller.panelContentViewForTesting else {
            Issue.record("Panel content view is missing")
            return
        }
        root.layoutSubtreeIfNeeded()

        guard let body = Self.findScrollView(in: root) else {
            Issue.record("Body scroll view is missing")
            return
        }

        let inset = PopupPanelGeometry.bodyContentInset
        let expectedLeading = PopupPanelGeometry.contentPadding + inset.width
        let expectedTop = PopupPanelGeometry.contentPadding + inset.height
        let expectedBottom = PopupPanelGeometry.bottomBarHeight
            + PopupPanelGeometry.contentPadding + inset.height

        let frame = body.convert(body.bounds, to: root)
        #expect(frame.minX == expectedLeading)
        #expect(root.bounds.maxX - frame.maxX == expectedLeading)
        // root は flipped でないため、上端は maxY 側にある。
        #expect(root.bounds.maxY - frame.maxY == expectedTop)
        #expect(frame.minY == expectedBottom)
    }

    private static func findScrollView(in root: NSView) -> NSScrollView? {
        if let scrollView = root as? NSScrollView { return scrollView }
        for subview in root.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
