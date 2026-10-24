import AppKit
import BrowserEngine
import Foundation
import Testing

private let paragraph = "<p>The river keeps its own time, rising in the wet months and falling back when the rains stop, and the town along its banks has learned, over a long history of floods, to build with that rhythm in mind.</p>"

@MainActor
@Suite(.serialized)
struct ReaderContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    private func articlePage() throws -> URL {
        try site.page("article.html", """
            <html><head><title>A river town</title><meta property="og:type" content="article"></head>
            <body><nav><a href="/">Home</a> <a href="/news">News</a></nav>
            <article><h1>A river town</h1>\(String(repeating: paragraph, count: 8))
            <script>window.ranInReader = true</script></article>
            <footer>Subscribe to our newsletter</footer></body></html>
            """)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func articlesOfferReaderMode(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try articlePage())
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        try await eventually { tab.state.isReaderAvailable }
        #expect(await tab.showReader())
        #expect(tab.state.isShowingReader)
        tab.hideReader()
        #expect(!tab.state.isShowingReader)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func shortPagesDont(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("short.html", "<p>Sign in to continue</p><input><input>"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(!tab.state.isReaderAvailable)
        #expect(await tab.showReader() == false)
        #expect(!tab.state.isShowingReader)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func loadingAnotherPageLeavesReaderMode(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try articlePage())
        try await eventually { tab.state.isReaderAvailable }
        #expect(await tab.showReader())
        let next = try site.page("next.html", "<p>Next</p>")
        tab.load(next)
        try await eventually { tab.state.url == next && !tab.state.isLoading }
        #expect(!tab.state.isShowingReader)
        #expect(!tab.state.isReaderAvailable)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pagesWithoutVideoDontFloat(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("still.html", "<p>No video here</p>"))
        #expect(await tab.enterPictureInPicture() == false)
        tab.exitPictureInPicture()
    }
}
