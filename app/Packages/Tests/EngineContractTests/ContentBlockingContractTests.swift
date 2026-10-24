import AppKit
import BrowserEngine
import Foundation
import Testing

private let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
private let blockBanner = ContentRuleSet(
    identifier: "brow-test-banner",
    json: #"[{"trigger":{"url-filter":"ad-banner\\.png"},"action":{"type":"block"}}]"#
)

@MainActor
@Suite(.serialized)
struct ContentBlockingContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    /// A page whose title says whether its banner image loaded.
    private func bannerPage() throws -> URL {
        try pixel.write(to: site.folder.appending(path: "ad-banner.png"))
        return try site.page("banner.html", #"<img src="ad-banner.png" onload="document.title='loaded'" onerror="document.title='blocked'">"#)
    }

    private func blocking(_ engine: EngineUnderTest) throws -> any ContentBlockingEngine {
        try #require(engine.make() as? any ContentBlockingEngine)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func installedRulesBlockMatchingLoads(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        try await browser.installContentRules([blockBanner])
        let tab = try await loadedTab(browser, try bannerPage())
        try await eventually { tab.state.title == "blocked" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pagesLoadNormallyWithoutRules(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let tab = try await loadedTab(browser, try bannerPage())
        try await eventually { tab.state.title == "loaded" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func aSiteWithBlockingOffLoadsEverything(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        try await browser.installContentRules([blockBanner])
        browser.isContentBlockingEnabled = { _ in false }
        let tab = try await loadedTab(browser, try bannerPage())
        try await eventually { tab.state.title == "loaded" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func installingAgainReplacesTheOldRules(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        try await browser.installContentRules([blockBanner])
        let tab = try await loadedTab(browser, try bannerPage())
        try await eventually { tab.state.title == "blocked" }
        try await browser.installContentRules([])
        tab.reload()
        try await eventually { tab.state.title == "loaded" }
    }

    /// A page whose title becomes its `#ad` element's `display` half a second after loading.
    private func adPage() throws -> URL {
        try site.page("ad.html", """
            <div id="ad">x</div>
            <script>setTimeout(() => { document.title = getComputedStyle(document.getElementById('ad')).display }, 500)</script>
            """)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pageScriptsHideElements(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        browser.pageScripts = { _, _ in PageScripts(css: ["#ad"], extendedCss: [], js: [], scriptlets: []) }
        let tab = try await loadedTab(browser, try adPage())
        try await eventually { tab.state.title == "none" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pageScriptsAreSkippedWhenBlockingIsOff(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        browser.pageScripts = { _, _ in PageScripts(css: ["#ad"], extendedCss: [], js: [], scriptlets: []) }
        browser.isContentBlockingEnabled = { _ in false }
        let tab = try await loadedTab(browser, try adPage())
        try await eventually { tab.state.title == "block" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pagesCantReachTheBridge(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        browser.pageScripts = { _, _ in PageScripts(css: [], extendedCss: [], js: [], scriptlets: []) }
        let page = try site.page("probe.html", "<script>document.title = typeof window.webkit?.messageHandlers?.browContentBlocking</script>")
        let tab = try await loadedTab(browser, page)
        try await eventually { tab.state.title == "undefined" }
    }

    /// A link that opens in a new tab, here to a site with blocking off, mustn't change the blocking of the page you're on.
    @Test(arguments: EngineUnderTest.allCases)
    func linksOpenedElsewhereLeaveThisPageBlocking(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        try await browser.installContentRules([blockBanner])
        browser.isContentBlockingEnabled = { url in !url.lastPathComponent.hasPrefix("off") }
        try pixel.write(to: site.folder.appending(path: "ad-banner.png"))
        _ = try site.page("off.html", "<title>Off</title>")
        // Opens the link in a new tab, then adds a banner image once that tab has had time to load.
        let page = try site.page("on.html", """
            <a id="link" href="off.html" target="_blank">off</a>
            <script>
            setTimeout(() => { document.getElementById('link').click() }, 200);
            setTimeout(() => {
                const img = document.createElement('img');
                img.onload = () => { document.title = 'loaded' };
                img.onerror = () => { document.title = 'blocked' };
                img.src = 'ad-banner.png?late';
                document.body.appendChild(img);
            }, 800);
            </script>
            """)
        let delegate = RecordingDelegate()
        let tab = try await loadedTab(browser, page, delegate: delegate)
        try await eventually { tab.state.title == "blocked" || tab.state.title == "loaded" }
        #expect(delegate.opened.count == 1)
        #expect(tab.state.title == "blocked")
        #expect(tab.state.url == page)
    }

    private var flagScriptlet: PageScripts {
        PageScripts(css: [], extendedCss: [], js: [], scriptlets: [PageScriptlet(name: "set-constant", args: ["browTestFlag", "true"])])
    }

    private func probe(_ name: String) throws -> URL {
        try site.page(name, "<script>document.title = String(window.browTestFlag)</script>")
    }

    @Test(arguments: EngineUnderTest.allCases)
    func scriptletsRunBeforeThePagesFirstScript(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let rules = flagScriptlet
        browser.pageScripts = { _, _ in rules }
        let tab = try await loadedTab(browser, try probe("first.html"))
        try await eventually { tab.state.title == "true" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func earlyRulesFollowTheSiteSetting(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let rules = flagScriptlet
        browser.pageScripts = { _, _ in rules }
        browser.isContentBlockingEnabled = { _ in false }
        let tab = try await loadedTab(browser, try probe("first.html"))
        try await eventually { tab.state.title == "undefined" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func earlyRulesBelongToTheNewPage(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let rules = flagScriptlet
        browser.pageScripts = { page, _ in page.lastPathComponent == "a.html" ? rules : nil }
        let tab = try await loadedTab(browser, try probe("a.html"))
        try await eventually { tab.state.title == "true" }
        tab.load(try probe("b.html"))
        try await eventually { tab.state.url?.lastPathComponent == "b.html" && tab.state.title == "undefined" }
    }

    /// Like YouTube: scripts need a nonce, and Trusted Types are required.
    @Test(arguments: EngineUnderTest.allCases)
    func scriptletsRunUnderAStrictContentSecurityPolicy(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let rules = flagScriptlet
        browser.pageScripts = { _, _ in rules }
        let page = try site.page("strict.html", """
            <meta http-equiv="Content-Security-Policy" content="script-src 'nonce-n'; require-trusted-types-for 'script'">
            <script nonce="n">document.title = String(window.browTestFlag)</script>
            """)
        let tab = try await loadedTab(browser, page)
        try await eventually { tab.state.title == "true" || tab.state.title == "undefined" }
        #expect(tab.state.title == "true")
    }

    @Test(arguments: EngineUnderTest.allCases)
    func earlyRulesFollowRedirectsBackAndReload(engine: EngineUnderTest) async throws {
        let browser = try blocking(engine)
        let rules = flagScriptlet
        browser.pageScripts = { page, _ in page.lastPathComponent == "a.html" ? rules : nil }
        _ = try probe("b.html")
        let hop = try site.page("hop.html", "<script>location.replace('b.html')</script>")
        let tab = try await loadedTab(browser, try probe("a.html"))
        try await eventually { tab.state.title == "true" }
        tab.load(hop)
        try await eventually { tab.state.url?.lastPathComponent == "b.html" && tab.state.title == "undefined" }
        tab.goBack()
        try await eventually { tab.state.url?.lastPathComponent == "a.html" && tab.state.title == "true" }
        tab.reload()
        try await Task.sleep(for: .milliseconds(500))
        try await eventually { tab.state.title == "true" }
        let restored = browser.makeTab(restoring: tab.snapshot())
        try await eventually { restored.state.url?.lastPathComponent == "a.html" && restored.state.title == "true" }
    }
}

