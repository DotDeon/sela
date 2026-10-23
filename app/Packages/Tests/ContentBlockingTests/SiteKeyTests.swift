import Foundation
import Testing
import ContentBlocking

@Test(arguments: [
    ("https://news.bbc.co.uk/x", "bbc.co.uk"),
    ("https://www.fnb.co.za/", "fnb.co.za"),
    ("http://localhost:8080/", "localhost"),
    ("https://Shop.Example.COM/", "example.com"),
    ("http://192.168.1.10/admin", "192.168.1.10"),
])
func contentBlockingSites(url: String, site: String) {
    #expect(contentBlockingSite(for: URL(string: url)!) == site)
}

@Test func urlsWithoutAHostHaveNoSite() {
    #expect(contentBlockingSite(for: URL(string: "about:blank")!) == nil)
}
