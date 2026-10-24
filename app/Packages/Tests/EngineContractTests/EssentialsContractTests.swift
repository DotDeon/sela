import AppKit
import BrowserEngine
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct EssentialsContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    @Test(arguments: EngineUnderTest.allCases)
    func findMatchesTextOnThePage(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("text.html", "<p>Hello there</p>"))
        #expect(await tab.find("there", backwards: false))
        #expect(await tab.find("absent", backwards: false) == false)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func findIgnoresCase(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("text.html", "<p>Hello there</p>"))
        #expect(await tab.find("HELLO", backwards: false))
    }

    @Test(arguments: EngineUnderTest.allCases)
    func downloadsArriveWhereTheDelegateSays(engine: EngineUnderTest) async throws {
        // A file WebKit can't show is downloaded, the same way a server's attachment is.
        try Data("hello download".utf8).write(to: site.folder.appending(path: "data.bin"))
        let page = try site.page("dl.html", """
            <a id="d" href="data.bin">get</a>
            <script>setTimeout(() => document.getElementById('d').click(), 200)</script>
            """)
        let target = FileManager.default.temporaryDirectory.appending(path: "brow-dl-\(UUID().uuidString)/data.bin")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let delegate = DownloadingDelegate(destination: target)
        let tab = engine.make().makeTab(url: nil)
        tab.delegate = delegate
        tab.load(page)
        try await eventually { delegate.download?.state == .finished(target) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "hello download")
        #expect(delegate.suggestedName == "data.bin")
        #expect(!FileManager.default.fileExists(atPath: target.path + ".download"))
        _ = tab
    }
}

extension EssentialsContractTests {
    @Test(arguments: EngineUnderTest.allCases)
    func cancellingEndsTheDownloadAndRemovesItsFile(engine: EngineUnderTest) async throws {
        let server = try SlowServer()
        let target = FileManager.default.temporaryDirectory.appending(path: "brow-dl-\(UUID().uuidString)/slow.bin")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let delegate = DownloadingDelegate(destination: target)
        let tab = engine.make().makeTab(url: nil)
        tab.delegate = delegate
        tab.load(server.url)
        try await eventually { (delegate.download?.progress ?? 0) > 0.01 }
        delegate.download?.cancel()
        try await eventually { delegate.download?.state == .cancelled }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: target.path + ".download"))
        #expect(!FileManager.default.fileExists(atPath: target.path))
        _ = server
    }
}

@MainActor
final class DownloadingDelegate: BrowserTabDelegate {
    let destination: URL
    private(set) var download: (any BrowserDownload)?
    private(set) var suggestedName: String?
    init(destination: URL) { self.destination = destination }
    func tabStateDidChange(_ tab: any BrowserTab) {}
    func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {}
    func tabDidRequestClose(_ tab: any BrowserTab) {}
    func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult { .dismissed }
    func tab(_ tab: any BrowserTab, didStartDownload download: any BrowserDownload, suggestedFilename: String) async -> URL? {
        self.download = download
        suggestedName = suggestedFilename
        return destination
    }
}

