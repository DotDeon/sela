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

    /// A short clip that ships with macOS, so the test needs no video of its own.
    nonisolated private static let clip = URL(fileURLWithPath: "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-8231-Case-mov/Banner-PID-8231-Case-Loop.mov")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: clip.path)), arguments: EngineUnderTest.allCases)
    func playingVideosFloatAndComeBack(engine: EngineUnderTest) async throws {
        try FileManager.default.copyItem(at: Self.clip, to: site.folder.appending(path: "clip.mov"))
        let page = try site.page("video.html", #"<video src="clip.mov" muted loop autoplay playsinline width="320" height="180"></video>"#)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let tab = try await loadedTab(engine.make(), page)
        window.contentView = tab.contentView
        window.orderFront(nil)
        // The clip needs a moment to start playing.
        var floated = false
        for _ in 0..<40 where !floated {
            try await Task.sleep(for: .milliseconds(100))
            floated = await tab.enterPictureInPicture()
        }
        #expect(floated)
        // Already floating, so there's nothing more to float.
        #expect(await tab.enterPictureInPicture() == false)
        tab.exitPictureInPicture()
        // Back in the page, the video can float again once the window has gone.
        var floatedAgain = false
        for _ in 0..<40 where !floatedAgain {
            try await Task.sleep(for: .milliseconds(100))
            floatedAgain = await tab.enterPictureInPicture()
        }
        #expect(floatedAgain)
        #expect(await tab.isPlayingMedia())
        tab.exitPictureInPicture()
        try await Task.sleep(for: .milliseconds(500))
    }
}
