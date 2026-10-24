import Foundation
import Testing
import BrowserEngine
import WebKit
@testable import WebKitEngine

private let work = ProfileIdentifier(rawValue: "6F1D4C56-1D7B-4B7E-9A55-2C5C1F0B9E10")
private let home = ProfileIdentifier(rawValue: "0D7F3E7A-9B8C-4D1E-8F2A-3B4C5D6E7F80")

@MainActor @Test func eachProfileGetsItsOwnStore() {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    #expect(engine.dataStore(for: work) === engine.dataStore(for: work))
    #expect(engine.dataStore(for: work) !== engine.dataStore(for: home))
    #expect(engine.dataStore(for: work) !== engine.dataStore(for: .default))
}

@MainActor @Test func tabsUseTheirProfilesStore() throws {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    let tab = try #require(engine.makeTab(url: nil, profile: work) as? WebKitTab)
    #expect(tab.profile == work)
    #expect(tab.webView.configuration.websiteDataStore === engine.dataStore(for: work))
    let plain = try #require(engine.makeTab(url: nil) as? WebKitTab)
    #expect(plain.profile == .default)
    #expect(plain.webView.configuration.websiteDataStore === engine.dataStore(for: .default))
    tab.close()
    plain.close()
}

@MainActor @Test func cookiesStayInTheirProfile() async throws {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    let cookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "session", .value: "work"]))
    await engine.dataStore(for: work).httpCookieStore.setCookie(cookie)
    #expect(await engine.dataStore(for: work).httpCookieStore.allCookies().map(\.name) == ["session"])
    #expect(await engine.dataStore(for: home).httpCookieStore.allCookies().isEmpty)
    #expect(await engine.dataStore(for: .default).httpCookieStore.allCookies().isEmpty)
}

@MainActor @Test func removingAProfileForgetsItsStore() async throws {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    let cookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "session", .value: "work"]))
    let before = engine.dataStore(for: work)
    await before.httpCookieStore.setCookie(cookie)
    await engine.removeWebsiteData(of: work)
    #expect(await before.httpCookieStore.allCookies().isEmpty)
    #expect(engine.dataStore(for: work) !== before)
}

@Test func storeIdentifiersAreStable() {
    #expect(WebKitEngine.storeIdentifier(for: work).uuidString == work.rawValue)
    let odd = ProfileIdentifier(rawValue: "work")
    #expect(WebKitEngine.storeIdentifier(for: odd) == WebKitEngine.storeIdentifier(for: odd))
    #expect(WebKitEngine.storeIdentifier(for: odd) != WebKitEngine.storeIdentifier(for: ProfileIdentifier(rawValue: "home")))
}
