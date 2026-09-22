//
//  PanelDragOverlayView.swift
//  IOW
//
//  訳文ポップアップの余白だけドラッグを受け付ける overlay。
//

import Cocoa

/// ポップアップ前面に載せ、余白だけドラッグを受け付ける overlay。
///
/// `hitTest` で本文・ボタン領域は `nil` を返して透過し、それ以外の余白だけ掴める。
final class PanelDragOverlayView: NSView {

    var onDragWillBegin: (() -> Void)?
    var onDragDidEnd: (() -> Void)?

    private let contentPadding: CGFloat
    private let bottomBarHeight: CGFloat
    private let bottomBarTrailingInset: CGFloat = 6
    private let bottomBarBottomInset: CGFloat
    private let bottomBarIconSize: CGFloat

    /// ドラッグ開始時のマウス位置（スクリーン座標）とウィンドウ原点。
    private var dragStartMouseScreenLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    init(
        contentPadding: CGFloat,
        bottomBarHeight: CGFloat,
        bottomBarBottomInset: CGFloat,
        bottomBarIconSize: CGFloat
    ) {
        self.contentPadding = contentPadding
        self.bottomBarHeight = bottomBarHeight
        self.bottomBarBottomInset = bottomBarBottomInset
        self.bottomBarIconSize = bottomBarIconSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), isDraggable(at: point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in draggableRects() {
            addCursorRect(rect, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onDragWillBegin?()
        dragStartMouseScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let dragStartMouseScreenLocation,
              let dragStartWindowOrigin else { return }
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - dragStartMouseScreenLocation.x
        let deltaY = currentMouse.y - dragStartMouseScreenLocation.y
        window.setFrameOrigin(NSPoint(
            x: dragStartWindowOrigin.x + deltaX,
            y: dragStartWindowOrigin.y + deltaY
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouseScreenLocation = nil
        dragStartWindowOrigin = nil
        onDragDidEnd?()
    }

    /// 指定座標がドラッグ可能な余白か（AppKit 座標系: 原点は左下）。
    private func isDraggable(at point: NSPoint) -> Bool {
        draggableRects().contains { $0.contains(point) }
    }

    /// ドラッグ可能な矩形一覧。本文スクロール領域と下部バーのボタン帯は含めない。
    private func draggableRects() -> [NSRect] {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return [] }

        // 右端のボタン帯。いまはコピー 1 つだけなので、幅はアイコン 1 個分である。
        // 複数個の幅と間隔を数える計算を持っていたが、ボタンが 1 つになって
        // 間隔の項が常に 0 になったため畳んだ。
        let trailingIconAreaWidth = bottomBarIconSize
        let trailingIconAreaRect = NSRect(
            x: width - bottomBarTrailingInset - trailingIconAreaWidth,
            y: bottomBarBottomInset,
            width: trailingIconAreaWidth,
            height: bottomBarIconSize
        )

        var rects: [NSRect] = []

        // 上端余白
        rects.append(NSRect(x: 0, y: height - contentPadding, width: width, height: contentPadding))

        // 下端バー（右端のボタン帯より左の空き）。
        //
        // ボタンは右端のコピーだけなので、左端から帯の手前までがそのまま掴める。
        let gapWidth = max(0, trailingIconAreaRect.minX)
        if gapWidth > 0 {
            rects.append(NSRect(x: 0, y: 0, width: gapWidth, height: bottomBarHeight))
        }

        // 左右余白
        let sideMinY = bottomBarHeight + contentPadding
        let sideHeight = max(0, height - contentPadding - sideMinY)
        if sideHeight > 0 {
            rects.append(NSRect(x: 0, y: sideMinY, width: contentPadding, height: sideHeight))
            rects.append(NSRect(x: width - contentPadding, y: sideMinY, width: contentPadding, height: sideHeight))
        }

        // 本文と下部バー間の余白
        let gapBetweenWidth = max(0, width - contentPadding * 2)
        if gapBetweenWidth > 0 {
            rects.append(NSRect(x: contentPadding, y: bottomBarHeight, width: gapBetweenWidth, height: contentPadding))
        }

        return rects
    }
}
