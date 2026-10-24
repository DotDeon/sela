import Browsing
import Foundation

/// How well `query` matches `text`: every query word must appear. A word that starts a word of the text
/// scores 2, one found elsewhere scores 1. Nil when any word is missing. Web address prefixes are ignored.
public func matchScore(_ query: String, _ text: String) -> Int? {
    let words = queryWords(query)
    guard !words.isEmpty else { return nil }
    let haystack = stripWebPrefixes(text.lowercased())
    let textWords = haystack.split { !$0.isLetter && !$0.isNumber }
    var total = 0
    for word in words {
        if textWords.contains(where: { $0.hasPrefix(word) }) {
            total += 2
        } else if haystack.contains(word) {
            total += 1
        } else {
            return nil
        }
    }
    return total
}

/// Command bar rows for a query, in display order:
/// the typed address or search (after a tab that matches every word as a word start), then up to 5 tabs,
/// 3 commands, 3 archived tabs and 5 history pages. An empty query shows the 6 most recently active tabs.
public func commandBarResults(
    query: String,
    tabs: [TabCandidate],
    commands: [CommandCandidate],
    archived: [ArchivedCandidate],
    history: [HistoryCandidate],
    searchEngine: SearchEngine = SearchEngineSettings().engine
) -> [CommandBarResult] {
    let words = queryWords(query)
    guard !words.isEmpty else {
        return tabs.sorted(by: moreRecent).prefix(6).map(CommandBarResult.tab)
    }

    let rankedTabs = ranked(tabs, by: { "\($0.title) \($0.url?.absoluteString ?? "")" }, query: query, tieBreak: moreRecent)
    let openURLs = Set(tabs.compactMap(\.url))
    let rankedCommands = ranked(commands, by: { ([$0.title] + $0.keywords).joined(separator: " ") }, query: query)
    let rankedArchived = ranked(archived.filter { $0.url.map { !openURLs.contains($0) } ?? true }, by: { "\($0.title) \($0.url?.absoluteString ?? "")" }, query: query)
    let rankedHistory = ranked(history.filter { !openURLs.contains($0.url) }, by: { "\($0.title) \($0.url.absoluteString)" }, query: query)

    var results: [CommandBarResult] = []
    var tabRows = rankedTabs.prefix(5).map { CommandBarResult.tab($0.item) }
    // Only the title and host can make a top hit, so a word that happens to be in an address path
    // ("docs", "com") still searches.
    if let best = rankedTabs.first, matchScore(query, "\(best.item.title) \(best.item.url?.host() ?? "")") == 2 * words.count {
        results.append(tabRows.removeFirst())
    }
    if let url = AddressInput.resolve(query, searchEngine: searchEngine) {
        results.append(.open(url, search: searchEngine.isSearch(url) ? searchEngine : nil))
    }
    results += tabRows
    results += rankedCommands.prefix(3).map { .command($0.item) }
    results += rankedArchived.prefix(3).map { .archived($0.item) }
    results += rankedHistory.prefix(5).map { .history($0.item) }
    return results
}

// MARK: Helpers

private func queryWords(_ query: String) -> [String] {
    stripWebPrefixes(query.lowercased()).split(whereSeparator: \.isWhitespace).map(String.init)
}

private func stripWebPrefixes(_ text: String) -> String {
    text.replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "www.", with: "")
}

/// Matching items, best score first. Ties keep `tieBreak` order, or input order without one.
private func ranked<Item>(_ items: [Item], by text: (Item) -> String, query: String, tieBreak: ((Item, Item) -> Bool)? = nil) -> [(item: Item, score: Int)] {
    items.enumerated()
        .compactMap { offset, item in matchScore(query, text(item)).map { (item: item, score: $0, offset: offset) } }
        .sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if let tieBreak, tieBreak(a.item, b.item) != tieBreak(b.item, a.item) { return tieBreak(a.item, b.item) }
            return a.offset < b.offset
        }
        .map { (item: $0.item, score: $0.score) }
}

private func moreRecent(_ a: TabCandidate, _ b: TabCandidate) -> Bool {
    (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
}
