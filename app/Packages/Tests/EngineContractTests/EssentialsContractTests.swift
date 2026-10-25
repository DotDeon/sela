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
    func pdfHoldsThePage(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("pdf.html", "<p>Printed words</p>"))
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let data = try await tab.pdf()
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(tab.printOperation(with: NSPrintInfo()) != nil)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pageZoomShowsInTheState(engine: EngineUnderTest) async throws {
        let delegate = RecordingDelegate()
        let tab = try await loadedTab(engine.make(), try site.page("zoom.html", "<p>Zoomed</p>"), delegate: delegate)
        #expect(tab.state.pageZoom == 1)
        let changes = delegate.stateChanges
        tab.setPageZoom(1.5)
        #expect(tab.state.pageZoom == 1.5)
        #expect(delegate.stateChanges == changes + 1)
        tab.setPageZoom(1.5)
        #expect(delegate.stateChanges == changes + 1, "setting the same level again is quiet")
    }

    @Test(arguments: EngineUnderTest.allCases)
    func soundShowsInTheStateAndMutes(engine: EngineUnderTest) async throws {
        try toneWAV(seconds: 30).write(to: site.folder.appending(path: "tone.wav"))
        let page = try site.page("sound.html", "<audio id=\"a\" src=\"tone.wav\" loop></audio><script>document.getElementById('a').play()</script>")
        let tab = engine.make().makeTab(url: nil)
        // Pages only play once they're on screen, as a tab is.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tab.contentView
        window.orderFront(nil)
        defer { window.close() }
        tab.load(page)
        try await eventually { tab.state.isPlayingAudio }
        #expect(!tab.state.isMuted)
        tab.setMuted(true)
        #expect(tab.state.isMuted)
        tab.setMuted(false)
        #expect(!tab.state.isMuted)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func downloadsArriveWhereTheDelegateSays(engine: EngineUnderTest) async throws {
        // A file WebKit can't show is downloaded, the same way a server's attachment is.
        try Data("hello download".utf8).write(to: site.folder.appending(path: "data.bin"))
        let page = try site.page("dl.html", """
            <a id="d" href="data.bin">get</a>
            <script>setTimeout(() => document.getElementById('d').click(), 200)</script>
            """)
        let target = FileManager.default.temporaryDirectory.appending(path: "sela-dl-\(UUID().uuidString)/data.bin")
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
        let target = FileManager.default.temporaryDirectory.appending(path: "sela-dl-\(UUID().uuidString)/slow.bin")
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

/// A quiet 440 Hz tone as a 16-bit mono WAV file, for pages that need something to play.
private func toneWAV(seconds: Int) -> Data {
    let rate = 8000
    let samples = rate * seconds
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: "RIFF".utf8)
    append(UInt32(36 + samples * 2))
    data.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(rate))
    append(UInt32(rate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: "data".utf8)
    append(UInt32(samples * 2))
    for index in 0..<samples {
        append(Int16(sin(Double(index) / Double(rate) * 440 * 2 * .pi) * 3000))
    }
    return data
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

