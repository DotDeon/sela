import Foundation
import Testing
import Browsing
import SelaTestSupport
import SidebarModel
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
        case .open(_, let search): search == nil ? "open" : "search"
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
    #expect(results.first == .open(URL(string: "https://example.com")!, search: nil))
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

@Test func addressPathsDontMakeATopHit() {
    let docs = TabCandidate(id: "docs-tab", title: "Getting started", url: URL(string: "https://example.com/docs/intro"), lastActiveAt: nil)
    let results = commandBarResults(query: "docs", tabs: [docs], commands: [], archived: [], history: [])
    #expect(kinds(results) == ["search", "tab"])
}

@Test func hostsStillMakeATopHit() {
    let results = commandBarResults(query: "github", tabs: [tab("Pull requests", "github")], commands: [], archived: [], history: [])
    #expect(kinds(results).first == "tab")
}

@Test func folderNamesFindTheirTabs() {
    var inFolder = tab("Roadmap", "roadmap")
    inFolder.location = "Work / Planning"
    let results = commandBarResults(query: "planning", tabs: [inFolder, tab("Recipes", "recipes")], commands: [], archived: [], history: [])
    #expect(results.contains(.tab(inFolder)))
    #expect(!results.contains(.tab(tab("Recipes", "recipes"))))
}

@Test func locationsNameFavouritesAndFolders() throws {
    var document = fixtureDocument()
    try document.setTitle("fold", "Work")
    let inner = fixtureItem("inner", parent: "fold", kind: .folder(FolderInfo(icon: nil, isExpanded: false)))
    try document.insert(inner, into: "fold", at: nil)
    try document.insert(fixtureTab("deep", parent: "inner"), into: "inner", at: nil)
    #expect(tabLocation(of: "p2", in: document) == "Work")
    #expect(tabLocation(of: "deep", in: document) == "Work / Folder")
    #expect(tabLocation(of: "f1", in: document) == "Favourites")
    #expect(tabLocation(of: "p1", in: document) == nil)
    #expect(tabLocation(of: "u1", in: document) == nil)
}

@Test func searchesUseTheChosenEngine() {
    let results = commandBarResults(query: "what is swift", tabs: [], commands: [], archived: [], history: [], searchEngine: .duckDuckGo)
    #expect(results.first == .open(URL(string: "https://duckduckgo.com/?q=what%20is%20swift")!, search: .duckDuckGo))
}

/// An address that happens to be another engine's search opens as an address.
@Test func otherEnginesSearchesOpenAsAddresses() {
    let results = commandBarResults(query: "https://www.google.com/search?q=x", tabs: [], commands: [], archived: [], history: [], searchEngine: .bing)
    #expect(results.first == .open(URL(string: "https://www.google.com/search?q=x")!, search: nil))
}
