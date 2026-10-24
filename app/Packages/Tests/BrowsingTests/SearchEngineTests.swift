import Foundation
import Testing
import Browsing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-search-\(UUID().uuidString)")!
}

@Test(arguments: [
    (SearchEngine.google, "https://www.google.com/search?q=swift%20ui"),
    (.duckDuckGo, "https://duckduckgo.com/?q=swift%20ui"),
    (.bing, "https://www.bing.com/search?q=swift%20ui"),
    (.ecosia, "https://www.ecosia.org/search?q=swift%20ui"),
    (.kagi, "https://kagi.com/search?q=swift%20ui"),
    (.braveSearch, "https://search.brave.com/search?q=swift%20ui"),
    (.startpage, "https://www.startpage.com/sp/search?query=swift%20ui"),
])
func searchURLs(engine: SearchEngine, expected: String) {
    #expect(engine.searchURL(for: "swift ui")?.absoluteString == expected)
    #expect(engine.isSearch(URL(string: expected)!))
}

@Test(arguments: [
    ("c++ & rust", "c%2B%2B%20%26%20rust"),
    ("a=b?c#d", "a%3Db%3Fc%23d"),
    ("100%", "100%25"),
    ("%s", "%25s"),
    ("café 東京", "caf%C3%A9%20%E6%9D%B1%E4%BA%AC"),
    ("👋", "%F0%9F%91%8B"),
])
func queriesArePercentEncoded(query: String, encoded: String) {
    #expect(SearchEngine.duckDuckGo.searchURL(for: query)?.absoluteString == "https://duckduckgo.com/?q=" + encoded)
}

@Test func everyEngineHasADistinctName() {
    let names = SearchEngine.allCases.map(\.name)
    #expect(Set(names).count == names.count)
    #expect(SearchEngine.braveSearch.name == "Brave Search")
}

@Test func searchesOnOtherEnginesAreNotSearches() {
    #expect(!SearchEngine.bing.isSearch(URL(string: "https://www.google.com/search?q=x")!))
    #expect(!SearchEngine.google.isSearch(URL(string: "https://example.com")!))
}

@Test func defaultsToGoogle() {
    #expect(SearchEngineSettings(defaults: freshDefaults()).engine == .google)
}

@Test func choiceIsStored() {
    let defaults = freshDefaults()
    SearchEngineSettings(defaults: defaults).engine = .ecosia
    #expect(SearchEngineSettings(defaults: defaults).engine == .ecosia)
    #expect(defaults.string(forKey: SearchEngineSettings.key) == "ecosia")
}

@Test func unknownStoredEnginesFallBackToGoogle() {
    let defaults = freshDefaults()
    defaults.set("altavista", forKey: SearchEngineSettings.key)
    #expect(SearchEngineSettings(defaults: defaults).engine == .google)
    defaults.set(3, forKey: SearchEngineSettings.key)
    #expect(SearchEngineSettings(defaults: defaults).engine == .google)
}
