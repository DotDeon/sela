import Foundation
import Testing
@testable import RemoteSettings

private func decode(_ json: String) -> RemoteSettings? {
    RemoteSettings(json: Data(json.utf8))
}

@Test func readsAFullFile() throws {
    let settings = try #require(decode("""
    {
      "version": 1,
      "searchEngines": [{ "id": "mojeek", "name": "Mojeek", "template": "https://www.mojeek.com/search?q=%s" }],
      "defaults": { "searchEngine": "duckduckgo", "tabSleepMinutes": 60, "autoPictureInPicture": false },
      "features": { "newThing": true },
      "message": { "id": "welcome", "text": "Hello", "link": "https://dotdeon.github.io/sela", "style": "alert", "minimumVersion": "0.1.3" }
    }
    """))
    #expect(settings.searchEngines.map(\.id) == ["mojeek"])
    #expect(settings.defaults == RemoteDefaults(searchEngine: "duckduckgo", tabSleepMinutes: 60, autoPictureInPicture: false))
    #expect(settings.features == ["newThing": true])
    let message = try #require(settings.message)
    #expect(message.id == "welcome")
    #expect(message.style == .alert)
    #expect(message.link == URL(string: "https://dotdeon.github.io/sela"))
    #expect(message.minimumVersion == AppVersion("0.1.3"))
}

/// The published file holds the values Sela ships with, so it changes nothing.
@Test func theFileOnTheWebsiteMatchesTheBuiltInValues() throws {
    let file = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../website/public/remote-settings.json").standardized
    let settings = try #require(RemoteSettings(json: try Data(contentsOf: file)))
    #expect(settings == RemoteSettings(defaults: RemoteDefaults(searchEngine: "google", tabSleepMinutes: 15, autoPictureInPicture: true)))
}

@Test(arguments: ["", "[]", "{}", #"{ "version": 2 }"#, #"{ "version": "1" }"#, "not json"])
func filesWithoutVersionOneAreRefused(json: String) {
    #expect(decode(json) == nil)
}

@Test func unknownKeysAreIgnored() {
    #expect(decode(#"{ "version": 1, "somethingNew": { "a": 1 }, "defaults": { "later": true } }"#) == .empty)
}

@Test func wrongTypesDropOnlyTheirOwnField() throws {
    let settings = try #require(decode("""
    {
      "version": 1,
      "searchEngines": { "id": "x" },
      "defaults": { "searchEngine": 3, "tabSleepMinutes": "60", "autoPictureInPicture": 1 },
      "features": { "good": true, "bad": "yes", "number": 0 },
      "message": "hello"
    }
    """))
    #expect(settings.searchEngines.isEmpty)
    #expect(settings.defaults == RemoteDefaults())
    #expect(settings.features == ["good": true])
    #expect(settings.message == nil)
}

@Test func wrongTypesBesideGoodValuesKeepTheGoodOnes() throws {
    let settings = try #require(decode("""
    { "version": 1, "defaults": { "searchEngine": true, "tabSleepMinutes": 5 }, "features": [] }
    """))
    #expect(settings.defaults == RemoteDefaults(tabSleepMinutes: 5))
    #expect(settings.features.isEmpty)
}

@Test func badEnginesAreDroppedOneByOne() throws {
    let settings = try #require(decode("""
    {
      "version": 1,
      "searchEngines": [
        { "id": "good", "name": "Good", "template": "https://good.example/?q=%s" },
        { "id": "plain", "name": "Plain", "template": "http://plain.example/?q=%s" },
        { "id": "noquery", "name": "No query", "template": "https://noquery.example/" },
        { "id": "script", "name": "Script", "template": "javascript:alert(%s)" },
        { "id": "Upper Case", "name": "Bad id", "template": "https://bad.example/?q=%s" },
        { "id": "unnamed", "name": " ", "template": "https://unnamed.example/?q=%s" },
        { "id": "number", "name": 4, "template": "https://number.example/?q=%s" },
        "string"
      ]
    }
    """))
    #expect(settings.searchEngines.map(\.id) == ["good"])
}

@Test func messagesWithUnreadableLinksOrVersionsAreDropped() {
    for extra in [#""link": "http://example.com""#, #""link": 3"#, #""minimumVersion": "one""#, #""maximumVersion": 2"#] {
        let settings = decode(#"{ "version": 1, "message": { "id": "m", "text": "Hi", \#(extra) } }"#)
        #expect(settings?.message == nil, "\(extra)")
    }
}

@Test func messagesDefaultToABanner() {
    let settings = decode(#"{ "version": 1, "message": { "id": "m", "text": "Hi", "style": "shout" } }"#)
    #expect(settings?.message?.style == .banner)
}

@Test func messagesNeedAnIdAndText() {
    #expect(decode(#"{ "version": 1, "message": { "text": "Hi" } }"#)?.message == nil)
    #expect(decode(#"{ "version": 1, "message": { "id": "m", "text": "  " } }"#)?.message == nil)
}
