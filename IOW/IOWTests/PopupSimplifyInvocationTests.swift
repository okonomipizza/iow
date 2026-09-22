//
//  PopupSimplifyInvocationTests.swift
//  IOWTests
//
//  Simplify 起動がエンジンを呼ぶことの検証。
//

import Foundation
import Testing
@testable import IOW

/// 呼び出し回数だけを数えるテスト用エンジン（Simplify 成功経路用）。
@MainActor
private final class CountingSimplifyTranslator: Translator, Simplifier {
    private(set) var translateCallCount = 0
    private(set) var simplifyCallCount = 0

    func translate(
        _ text: String,
        to target: Language
    ) -> AsyncThrowingStream<String, Error> {
        translateCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield("translated")
            continuation.finish()
        }
    }

    func simplify(_ text: String) -> AsyncThrowingStream<String, Error> {
        simplifyCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield("simplified")
            continuation.finish()
        }
    }
}

/// Simplify の同言語スキップは無く、どちらのモードもエンジンを呼ぶことの検証。
@MainActor
struct PopupSimplifyInvocationTests {

    @Test func startSimplifyCallsTheSimplifierEvenWhenSourceLooksLikeEnglish() async throws {
        let counting = CountingSimplifyTranslator()
        let controller = SelectionTextPopupPanelController(
            translator: counting
        )
        defer { controller.dismiss() }

        controller.startSimplify(text: "Hello world")

        // ストリーム消費タスクが simplify を呼び終わるまで短く待つ。
        let called = await waitUntil({ counting.simplifyCallCount >= 1 }, within: .seconds(2))
        #expect(called)
        #expect(counting.simplifyCallCount == 1)
        #expect(counting.translateCallCount == 0)
    }

    private func waitUntil(
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
