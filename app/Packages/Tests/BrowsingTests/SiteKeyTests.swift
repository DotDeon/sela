import Testing
import Browsing

@Test(arguments: [
    ("mail.google.com", "google.com"),
    ("www.fnb.co.za", "fnb.co.za"),
    ("online.fnb.co.za", "fnb.co.za"),
    ("bbc.co.uk", "bbc.co.uk"),
    ("news.bbc.co.uk", "bbc.co.uk"),
    ("localhost", "localhost"),
    ("192.168.1.10", "192.168.1.10"),
    ("GitHub.COM", "github.com"),
    ("chat.t3.gg", "t3.gg"),
    ("console.x.ai", "x.ai"),
])
func siteKeys(host: String, key: String) {
    #expect(siteKey(forHost: host) == key)
}
