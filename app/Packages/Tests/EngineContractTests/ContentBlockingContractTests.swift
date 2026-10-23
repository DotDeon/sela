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
}
