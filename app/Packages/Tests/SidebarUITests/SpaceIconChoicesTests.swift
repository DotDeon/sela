import AppKit
import Testing
@testable import SidebarUI

private func isSymbol(_ name: String) -> Bool { NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil }

@Test func everyOfferedSymbolExists() {
    let missing = spaceSymbolChoices.map(\.name).filter { !isSymbol($0) }
    #expect(missing.isEmpty)
    #expect(Set(spaceSymbolChoices.map(\.name)).count == spaceSymbolChoices.count)
    #expect(Set(spaceEmojiChoices).count == spaceEmojiChoices.count)
}

@Test func anEmptyQueryShowsEverything() {
    #expect(spaceIconChoices(.symbols, matching: "", isSymbol: isSymbol).count == spaceSymbolChoices.count)
    #expect(spaceIconChoices(.emoji, matching: " ", isSymbol: isSymbol) == spaceEmojiChoices)
}

@Test func wordsFindSymbolsByNameOrKeyword() {
    let work = spaceIconChoices(.symbols, matching: "work", isSymbol: isSymbol)
    #expect(work.first == "briefcase.fill")
    #expect(spaceIconChoices(.symbols, matching: "music", isSymbol: isSymbol).contains("headphones"))
    #expect(spaceIconChoices(.symbols, matching: "zzzz", isSymbol: isSymbol).isEmpty)
}

@Test func unicodeNamesFindEmoji() {
    #expect(spaceIconChoices(.emoji, matching: "rocket", isSymbol: isSymbol) == ["🚀"])
    #expect(spaceIconChoices(.emoji, matching: "coffee", isSymbol: isSymbol) == ["☕️"])
    #expect(spaceIconChoices(.emoji, matching: "Work", isSymbol: isSymbol).contains("💼"))
}

/// Anything SF Symbols or emoji has can be chosen by typing it, even when the grid doesn't list it.
@Test func anExactSymbolOrEmojiComesFirst() {
    #expect(spaceIconChoices(.symbols, matching: "tortoise.fill", isSymbol: isSymbol) == ["tortoise.fill"])
    #expect(spaceIconChoices(.emoji, matching: "🦖", isSymbol: isSymbol) == ["🦖"])
    #expect(spaceIconChoices(.emoji, matching: "❤️", isSymbol: isSymbol).first == "❤️")
    #expect(spaceIconChoices(.emoji, matching: "a", isSymbol: isSymbol).first != "a")
}
