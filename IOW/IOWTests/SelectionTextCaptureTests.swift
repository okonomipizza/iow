//
//  SelectionTextCaptureTests.swift
//  IOWTests
//
//  ペーストボードスナップショットの往復だけを固定する（合成 Cmd+C は
//  前面アプリ依存のためここでは扱わない）。
//

import AppKit
import Testing

@testable import IOW

@MainActor
struct SelectionTextCaptureTests {

    @Test func pasteboardSnapshotRestoresStringContent() {
        let suitePasteboard = NSPasteboard.withUniqueName()
        defer { suitePasteboard.releaseGlobally() }

        suitePasteboard.clearContents()
        suitePasteboard.setString("hello-iow", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: suitePasteboard)
        suitePasteboard.clearContents()
        #expect(suitePasteboard.string(forType: .string) == nil)

        snapshot.restore(to: suitePasteboard)
        #expect(suitePasteboard.string(forType: .string) == "hello-iow")
    }
}
