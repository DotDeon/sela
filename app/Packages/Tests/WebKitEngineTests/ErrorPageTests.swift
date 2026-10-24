import Foundation
import Testing
@testable import WebKitEngine

private let failed = URL(string: "https://sela-test.invalid/page")!
private let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)

@Test func errorPageLinksTheGivenSearch() {
    let html = errorPageHTML(for: failed, error: error) { URL(string: "https://duckduckgo.com/?q=" + $0) }
    #expect(html.contains("<a href=\"https://duckduckgo.com/?q=sela-test.invalid\">Search for sela-test.invalid</a>"))
    #expect(!html.contains("google"))
}

@Test func errorPageWithoutASearchOnlyRetries() {
    let html = errorPageHTML(for: failed, error: error) { _ in nil }
    #expect(html.contains("Try again"))
    #expect(!html.contains("Search for"))
}
