import Foundation
import Testing
import Browsing

@Test(arguments: [
    ("example.com", "https://example.com"),
    ("  example.com/path?q=1  ", "https://example.com/path?q=1"),
    ("foo.dev", "https://foo.dev"),
    ("http://example.com", "http://example.com"),
    ("https://example.com/a b", "https://example.com/a%20b"),
    ("localhost:3000", "http://localhost:3000"),
    ("localhost", "http://localhost"),
    ("app.localhost:5173", "http://app.localhost:5173"),
    ("my-mac.local:3000", "http://my-mac.local:3000"),
    ("192.168.1.1:8080/admin", "http://192.168.1.1:8080/admin"),
    ("about:blank", "about:blank"),
    ("file:///Users/me/page.html", "file:///Users/me/page.html"),
    ("what is swift", "https://www.google.com/search?q=what%20is%20swift"),
    ("swift", "https://www.google.com/search?q=swift"),
    ("c++ & rust", "https://www.google.com/search?q=c%2B%2B%20%26%20rust"),
    ("version 1.2", "https://www.google.com/search?q=version%201.2"),
    ("1.5", "https://www.google.com/search?q=1.5"),
])
func resolves(input: String, expected: String) {
    #expect(AddressInput.resolve(input)?.absoluteString == expected)
}

@Test func searchesGoToTheChosenEngine() {
    #expect(AddressInput.resolve("what is swift", searchEngine: .kagi)?.absoluteString == "https://kagi.com/search?q=what%20is%20swift")
    #expect(AddressInput.resolve("swift", searchEngine: .startpage)?.absoluteString == "https://www.startpage.com/sp/search?query=swift")
    #expect(AddressInput.resolve("example.com", searchEngine: .kagi)?.absoluteString == "https://example.com")
}

@Test func blankInputResolvesToNil() {
    #expect(AddressInput.resolve("") == nil)
    #expect(AddressInput.resolve("   ") == nil)
}
