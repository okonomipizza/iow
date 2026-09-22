//
//  PopupTranslationCancellationTests.swift
//  IOWTests
//
//  ポップアップの dismiss と新しい翻訳の開始が、進行中の翻訳ストリームを
//  キャンセルすることの検証。
//

import Foundation
import Testing
@testable import IOW

/// 先頭チャンクを 1 つ流したあと、キャンセルされるまで待ち続けるテスト用エンジン。
///
/// 実エンジン（`GeminiTranslator`）は `URLSession` の読み込みで待っており、ストリームの
/// 消費者が止まれば `onTermination` → producer タスクのキャンセル → 読み込み中断、と
/// 伝播する。ここでは同じ性質を「producer タスク自身のキャンセル待ち」で再現する。
@MainActor
private final class StallingTranslator: Translator, Simplifier {

    /// 直近で生成したストリームの producer タスク。テストが生成を待つために保持する。
    var producerTask: Task<Void, Never>?

    /// 直近のストリームが最初のチャンクを送出済みか。
    ///
    /// 消費者（ポップアップのタスク）がストリームの 2 回目以降の待機に入った
    /// 「in-flight」状態の近似として待機の対象にする。
    private(set) var receivedFirstChunk = false

    /// producer の処理が最後まで進んだ（キャンセルが伝播した）回数の累計。
    ///
    /// 1 度の dismiss では立たない「古い producer だけが止まる」ことを観測するため、
    /// 終了のフラグではなく数を数える（新しい翻訳開始で古いストリームが止まるテスト用）。
    private(set) var terminatedProducerCount = 0

    func translate(
        _ text: String,
        to target: Language
    ) -> AsyncThrowingStream<String, Error> {
        stallingStream()
    }

    func simplify(_ text: String) -> AsyncThrowingStream<String, Error> {
        stallingStream()
    }

    private func stallingStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("first chunk")
                receivedFirstChunk = true
                // キャンセルされるまで待ち続ける。終わったら「終了」を記録してストリームを閉じる。
                // `translate` は MainActor 上（ポップアップのタスク内）から呼ばれるため、
                // この Task も MainActor で動き、フラグの書き込みと読み取りは競わない。
                defer {
                    continuation.finish()
                    terminatedProducerCount += 1
                }
                while !Task.isCancelled {
                    await Task.yield()
                }
            }
            // 消費者がストリームを手放したら producer を止める（実エンジンと同じ仕組み）。
            continuation.onTermination = { _ in task.cancel() }
            producerTask = task
        }
    }
}

/// ポップアップの `dismiss()` と新しい翻訳の開始が、翻訳ストリームの生成側まで
/// キャンセルを伝えることの検証。
@MainActor
struct PopupTranslationCancellationTests {

    @Test
    func dismissingThePopupCancelsTheInFlightTranslationStream() async throws {
        let stalling = StallingTranslator()
        let controller = SelectionTextPopupPanelController(
            translator: stalling
        )
        // 途中で #require が失敗しても、表示したパネルとイベントモニタを残さない。
        defer { controller.dismiss() }

        controller.startTranslation(text: "Hello", target: .english)
        // producer が最初のチャンクを送出し、consumer が in-flight に入るまで待つ。
        _ = try #require(
            await Self.waitForProducer(of: stalling, within: .seconds(2)),
            "startTranslation should begin consuming the translation stream"
        )

        controller.dismiss()

        // dismiss のキャンセルが producer へ伝播して終了することを、有限時間のポーリングで
        // 確認する。伝播しない実装（タスクを保持しない・cancel を呼ばない）では終わらない
        // ため、ここがタイムアウトで失敗する。
        let terminated = await Self.waitUntil(
            { stalling.terminatedProducerCount >= 1 },
            within: .seconds(2)
        )
        #expect(terminated, "dismiss should cancel the in-flight translation stream")
    }

    @Test
    func startingANewTranslationCancelsThePreviousOne() async throws {
        let stalling = StallingTranslator()
        let controller = SelectionTextPopupPanelController(
            translator: stalling
        )
        // 途中で #require が失敗しても、表示したパネルとイベントモニタを残さない。
        defer { controller.dismiss() }

        // 1 本目を開始し、in-flight の状態にする。
        controller.startTranslation(text: "Hello", target: .english)
        _ = try #require(
            await Self.waitForProducer(of: stalling, within: .seconds(2)),
            "the first startTranslation should begin consuming the translation stream"
        )

        // 2 本目の開始で 1 本目の producer が止まること。cancel を忘れた実装では
        // 1 本目が `terminatedProducerCount` を増やさず、ここがタイムアウトで失敗する。
        controller.startTranslation(text: "Good night", target: .english)
        let firstProducerEnded = await Self.waitUntil(
            { stalling.terminatedProducerCount >= 1 },
            within: .seconds(2)
        )
        #expect(firstProducerEnded, "a new translation should cancel the previous in-flight stream")
    }

    @Test
    func dismissingThePopupCancelsTheInFlightSimplificationStream() async throws {
        let stalling = StallingTranslator()
        let controller = SelectionTextPopupPanelController(
            translator: stalling
        )
        defer { controller.dismiss() }

        controller.startSimplify(text: "Hello")
        _ = try #require(
            await Self.waitForProducer(of: stalling, within: .seconds(2)),
            "startSimplify should begin consuming the simplification stream"
        )

        controller.dismiss()

        let terminated = await Self.waitUntil(
            { stalling.terminatedProducerCount >= 1 },
            within: .seconds(2)
        )
        #expect(terminated, "dismiss should cancel the in-flight simplification stream")
    }

    @Test
    func startingANewSimplificationCancelsThePreviousOne() async throws {
        let stalling = StallingTranslator()
        let controller = SelectionTextPopupPanelController(
            translator: stalling
        )
        defer { controller.dismiss() }

        controller.startSimplify(text: "Hello")
        _ = try #require(
            await Self.waitForProducer(of: stalling, within: .seconds(2)),
            "the first startSimplify should begin consuming the simplification stream"
        )

        controller.startSimplify(text: "Good night")
        let firstProducerEnded = await Self.waitUntil(
            { stalling.terminatedProducerCount >= 1 },
            within: .seconds(2)
        )
        #expect(firstProducerEnded, "a new simplification should cancel the previous in-flight stream")
    }

    /// `translator.translate` / `simplify` が呼ばれて最初のチャンクが送出されるまで待ち、
    /// 生成された producer タスクを返す。時間切れなら `nil`。
    private static func waitForProducer(
        of translator: StallingTranslator,
        within limit: Duration
    ) async -> Task<Void, Never>? {
        _ = await Self.waitUntil({ translator.receivedFirstChunk }, within: limit)
        return translator.producerTask
    }

    /// 述語が真になるか、制限時間内に真になるかを返す。
    ///
    /// タスクの完了を `task.value` で待つと、キャンセル未伝播のときに永遠に
    /// 待ち続けてしまうため、状態を有限時間のポーリングで観測する。
    private static func waitUntil(
        _ condition: @MainActor () -> Bool,
        within limit: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limit)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}
