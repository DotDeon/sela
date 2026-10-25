import Foundation
import Testing
import Browsing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-sitesearch-\(UUID().uuidString)")!
}

private let youtube = SiteSearch(name: "YouTube", shortcut: "yt", template: "https://www.youtube.com/results?search_query=%s")
private let wikipedia = SiteSearch(name: "Wikipedia", shortcut: "w", template: "https://en.wikipedia.org/w/index.php?search=%s")

@Test func shortcutASpaceAndAQueryMatch() throws {
    let match = try #require(SiteSearch.match("yt cats", in: [youtube, wikipedia]))
    #expect(match.site == youtube)
    #expect(match.query == "cats")
    #expect(match.site.searchURL(for: match.query)?.absoluteString == "https://www.youtube.com/results?search_query=cats")
}

@Test func matchingIgnoresCaseAndExtraSpaces() throws {
    let match = try #require(SiteSearch.match("  YT   cats and dogs  ", in: [youtube]))
    #expect(match.site == youtube)
    #expect(match.query == "cats and dogs")
}

@Test(arguments: ["yt", "yt ", "ytcats", "cats yt", "", "w"])
func textWithoutAShortcutAndQueryDoesntMatch(text: String) {
    #expect(SiteSearch.match(text, in: [youtube, wikipedia]) == nil)
}

@Test func queriesKeepTheirOwnPunctuation() {
    #expect(youtube.searchURL(for: "c++ & rust")?.absoluteString == "https://www.youtube.com/results?search_query=c%2B%2B%20%26%20rust")
}

@Test func templatesFollowTheSearchEngineRules() {
    #expect(SiteSearch.isValidTemplate("https://example.org/search?q=%s"))
    #expect(!SiteSearch.isValidTemplate("http://example.org/search?q=%s"), "https only")
    #expect(!SiteSearch.isValidTemplate("https://example.org/search"), "needs %s")
    #expect(!SiteSearch.isValidTemplate("https:///search?q=%s"), "needs a host")
    #expect(!SiteSearch.isValidTemplate("https://example.org/" + String(repeating: "a", count: 500) + "%s"), "too long")
}

@Test func shortcutsAreOneWordAndNamesArentBlank() {
    #expect(SiteSearch.isValidShortcut("yt"))
    #expect(!SiteSearch.isValidShortcut(""))
    #expect(!SiteSearch.isValidShortcut("you tube"))
    let long = String(repeating: "y", count: 21)
    #expect(!SiteSearch.isValidShortcut(long))
    #expect(SiteSearch.isValidName("YouTube"))
    #expect(!SiteSearch.isValidName("   "))
    #expect(youtube.isValid)
    #expect(!SiteSearch(name: "Bad", shortcut: "b", template: "nope").isValid)
}

@Test func theDefaultsAreValidAndHaveUniqueShortcuts() {
    let allValid = SiteSearch.defaults.allSatisfy { $0.isValid }
    #expect(allValid)
    #expect(Set(SiteSearch.defaults.map(\.shortcut)).count == SiteSearch.defaults.count)
    #expect(SiteSearch.defaults.map(\.shortcut) == ["yt", "gh", "w", "r", "a", "maps", "tw"])
}

@Test func settingsStartWithTheDefaults() {
    #expect(SiteSearchSettings(defaults: freshDefaults()).all == SiteSearch.defaults)
}

@Test func settingsAddReplaceAndRemove() {
    let defaults = freshDefaults()
    let settings = SiteSearchSettings(defaults: defaults)
    let maps = SiteSearch(name: "Google Maps", shortcut: "gm", template: "https://www.google.com/maps/search/%s")
    settings.save(maps)
    #expect(settings.all.count == SiteSearch.defaults.count + 1)
    #expect(SiteSearchSettings(defaults: defaults).all.last == maps)

    var renamed = maps
    renamed.name = "Maps"
    settings.save(renamed)
    #expect(settings.all.filter { $0.id == maps.id } == [renamed])

    settings.remove(maps.id)
    #expect(settings.all == SiteSearch.defaults)
    settings.remove(SiteSearch.defaults[0].id)
    #expect(settings.all.count == SiteSearch.defaults.count - 1, "removing a default sticks")
}

@Test func settingsRefuseInvalidSitesAndRestoreDefaults() {
    let defaults = freshDefaults()
    let settings = SiteSearchSettings(defaults: defaults)
    settings.save(SiteSearch(name: "Bad", shortcut: "b", template: "http://insecure.example/%s"))
    #expect(settings.all == SiteSearch.defaults)
    settings.remove(SiteSearch.defaults[0].id)
    settings.restoreDefaults()
    #expect(settings.all == SiteSearch.defaults)
}

@Test func unreadableStoredListFallsBackToDefaults() {
    let defaults = freshDefaults()
    defaults.set(Data("not json".utf8), forKey: SiteSearchSettings.key)
    #expect(SiteSearchSettings(defaults: defaults).all == SiteSearch.defaults)
}
