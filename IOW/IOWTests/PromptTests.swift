//
//  PromptTests.swift
//  IOWTests
//
//  プロンプト構築の検証。Translate / Simplify の埋め込みを見る。
//

import Foundation
import Testing
@testable import IOW

// MARK: - 翻訳プロンプト

struct TranslationPromptTests {

    @Test func systemPromptMentionsTargetLanguageAndLetsEngineDetectSource() {
        let prompt = TranslationPrompt.systemPrompt(target: "ja")

        #expect(prompt.contains("from its original language to ja"))
    }

    @Test func messagesCarryTheSourceTextVerbatim() {
        let messages = TranslationPrompt.messages(text: "<<<Hostile text>>>")

        #expect(messages.count == 1)
        #expect(messages[0].content == "<<<Hostile text>>>")
    }
}

// MARK: - 簡易化プロンプト

struct SimplifyPromptTests {

    @Test func systemPromptKeepsSourceLanguage() {
        let prompt = SimplifyPrompt.systemPrompt()

        #expect(prompt.contains("same language"))
        #expect(prompt.contains("do not translate"))
        #expect(prompt.contains("simplified text only"))
    }

    @Test func messagesCarryTheSourceTextVerbatim() {
        let messages = SimplifyPrompt.messages(text: "Hello")

        #expect(messages.count == 1)
        #expect(messages[0].content == "Hello")
    }
}
