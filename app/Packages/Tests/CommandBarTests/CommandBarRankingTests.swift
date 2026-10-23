import Foundation
import Testing
@testable import CommandBar

@Test(arguments: [
    ("inb", "Inbox – Gmail", 2 as Int?),
    ("box", "Inbox", 1),
    ("mail inbox", "Inbox – Gmail", 3),
    ("github", "https://www.github.com/x", 2),
    ("zzz", "Inbox", nil),
] as [(String, String, Int?)])
func scores(query: String, text: String, expected: Int?) {
    #expect(matchScore(query, text) == expected)
}

private func kinds(_ results: [CommandBarResult]) -> [String] {
    results.map { result in
        switch result {
        case .open(_, let isSearch): isSearch ? "search" : "open"
        case .tab: "tab"
        case .command: "command"
        case .archived: "archived"
        case .history: "history"
        }
    }
}

@Test func strongTabMatchComesFirst() {
    let results = commandBarResults(query: "inbox", tabs: [tab("Inbox – Gmail", "mail")], commands: [], archived: [], history: [])
    #expect(results.first == .tab(tab("Inbox – Gmail", "mail")))
    #expect(kinds(results) == ["tab", "search"])
}

@Test func searchComesFirstForSentences() {
    let results = commandBarResults(query: "what is swift", tabs: [tab("Swift.org", "swift")], commands: [], archived: [], history: [])
    #expect(kinds(results).first == "search")
}

@Test func addressesOpenDirectly() {
    let results = commandBarResults(query: "example.com", tabs: [], commands: [], archived: [], history: [])
    #expect(results.first == .open(URL(string: "https://example.com")!, isSearch: false))
}

@Test func groupsAreCappedAndOrdered() {
    let results = commandBarResults(
        query: "tem",
        tabs: (1...8).map { tab("Item \($0)") },
        commands: (1...4).map { command("Item command \($0)") },
        archived: (1...4).map { archived("Item archived \($0)") },
        history: (1...7).map { history("Item history \($0)") }
    )
    #expect(kinds(results) == ["search"] + Array(repeating: "tab", count: 5) + Array(repeating: "command", count: 3)
        + Array(repeating: "archived", count: 3) + Array(repeating: "history", count: 5))
}

@Test func tabsRankByScoreThenRecency() {
    let results = commandBarResults(query: "news", tabs: [tab("Old news", "old", minutesAgo: 60), tab("Fresh news", "fresh", minutesAgo: 1), tab("Newsletter", "letter", minutesAgo: 30)], commands: [], archived: [], history: [])
    let titles = results.compactMap { if case .tab(let t) = $0 { t.title } else { nil } }
    #expect(titles == ["Fresh news", "Newsletter", "Old news"])
}

@Test func historyAlreadyOpenIsDropped() {
    let open = tab("Docs", "docs")
    let results = commandBarResults(query: "docs", tabs: [open], commands: [], archived: [], history: [history("Docs", url: open.url!.absoluteString), history("Docs two")])
    let historyTitles = results.compactMap { if case .history(let h) = $0 { h.title } else { nil } }
    #expect(historyTitles == ["Docs two"])
}

@Test func emptyQueryShowsRecentTabs() {
    let tabs = (1...8).map { tab("Tab \($0)", "t\($0)", minutesAgo: Double($0)) }
    let results = commandBarResults(query: "  ", tabs: tabs, commands: [command("New Space")], archived: [], history: [history("x")])
    #expect(results == tabs.prefix(6).map(CommandBarResult.tab))
}
