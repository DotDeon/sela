import Foundation
import Testing
import BrowserEngine
import Browsing

private func state(url: String?, title: String?) -> TabState {
    var state = TabState.blank
    state.url = url.flatMap(URL.init(string:))
    state.title = title
    return state
}

@Test func usesTrimmedTitle() {
    #expect(displayTitle(for: state(url: "https://mail.example.com/", title: "  Inbox  ")) == "Inbox")
}

@Test func fallsBackToHost() {
    #expect(displayTitle(for: state(url: "https://mail.example.com/x", title: "")) == "mail.example.com")
}

@Test func blankTabIsNewTab() {
    #expect(displayTitle(for: state(url: nil, title: nil)) == "New Tab")
    #expect(displayTitle(for: state(url: "about:blank", title: nil)) == "New Tab")
}

@Test func fileURLUsesFileName() {
    #expect(displayTitle(for: state(url: "file:///Users/me/page.html", title: nil)) == "page.html")
}
