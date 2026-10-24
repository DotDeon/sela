import BrowserEngine
import FakeEngine
import Foundation
import Testing
import ContentBlocking

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let listText = """
    [Adblock Plus 2.0]
    ||ads.example.com^
    example.com#%#//scriptlet('abort-on-property-read', 'adsbygoogle')
    """

/// A list server that can fail, or hold every request until `release()`.
private actor Server {
    private var failing = false
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var fetches = 0

    func setFailing(_ value: Bool) { failing = value }
    func hold() { held = true }
    func release() {
        held = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func fetch(_ url: URL) async throws -> (Data, Int) {
        fetches += 1
        if held { await withCheckedContinuation { waiting.append($0) } }
        if failing { throw URLError(.notConnectedToInternet) }
        return (Data(listText.utf8), 200)
    }
}

@MainActor
private final class Clock {
    var now = start
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let server = Server()
    let clock = Clock()
    let folder: URL
    let defaults: UserDefaults

    init(defaults: UserDefaults? = nil, folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.temporaryDirectory.appending(path: "sela-blocking-\(UUID().uuidString)")
        self.defaults = defaults ?? UserDefaults(suiteName: "sela-tests-\(UUID().uuidString)")!
    }

    func makeStore() -> FilterListStore {
        let server = server
        let clock = clock
        return FilterListStore(folder: folder.appending(path: "lists"), now: { clock.now }, fetch: { try await server.fetch($0) })
    }

    func makeBlocker() -> ContentBlocker {
        ContentBlocker(engine: engine, store: makeStore(), workFolder: folder, defaults: defaults)
    }
}

/// Polls every 20 ms for up to 5 seconds.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<250 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

@MainActor @Test func startInstallsSavedListsBeforeDownloading() async throws {
    let h = Harness()
    await h.makeStore().refresh(FilterList.defaults)
    h.clock.now = start.addingTimeInterval(25 * 3600)
    await h.server.hold()
    let blocker = h.makeBlocker()
    let starting = Task { await blocker.start() }
    try await eventually { h.engine.installCount == 1 }
    #expect(h.engine.installedRuleSets.count == 2)
    await h.server.release()
    await starting.value
}

@MainActor @Test func firstLaunchOfflineBlocksNothingAndRecovers() async throws {
    let h = Harness()
    await h.server.setFailing(true)
    let blocker = h.makeBlocker()
    await blocker.start()
    #expect(h.engine.installCount == 0)
    await h.server.setFailing(false)
    await blocker.refreshIfNeeded()
    #expect(h.engine.installedRuleSets.count == 2)
}

@MainActor @Test func blockingIsOnByDefault() {
    let blocker = Harness().makeBlocker()
    #expect(blocker.isEnabled)
    #expect(blocker.isBlocking(on: URL(string: "https://a.example.com/")!))
}

@MainActor @Test func turningASiteOffCoversItsSubdomains() {
    let h = Harness()
    let blocker = h.makeBlocker()
    blocker.setBlocking(false, forSiteOf: URL(string: "https://www.example.com/")!)
    #expect(!blocker.isBlocking(on: URL(string: "https://shop.example.com/")!))
    #expect(blocker.isBlocking(on: URL(string: "https://example.org/")!))
    #expect(!h.makeBlocker().isBlocking(on: URL(string: "https://example.com/")!))
    blocker.setBlocking(true, forSiteOf: URL(string: "https://example.com/")!)
    #expect(blocker.isBlocking(on: URL(string: "https://shop.example.com/")!))
}

@MainActor @Test func turningBlockingOffGloballyStopsEverySite() async throws {
    let h = Harness()
    let blocker = h.makeBlocker()
    await blocker.start()
    blocker.setEnabled(false)
    #expect(!blocker.isEnabled)
    #expect(h.engine.isContentBlockingEnabled?(URL(string: "https://a.example.com/")!) == false)
    #expect(h.makeBlocker().isEnabled == false)
}

@MainActor @Test func pageScriptsFollowTheSiteSetting() async throws {
    let h = Harness()
    let blocker = h.makeBlocker()
    await blocker.start()
    let page = URL(string: "https://example.com/")!
    #expect(h.engine.pageScripts?(page, nil)?.scriptlets.map(\.name) == ["abort-on-property-read"])
    blocker.setBlocking(false, forSiteOf: page)
    #expect(h.engine.pageScripts?(page, nil) == nil)
}

@MainActor @Test func missingListsAreReportedUntilDownloaded() async throws {
    let h = Harness()
    await h.server.setFailing(true)
    let blocker = h.makeBlocker()
    await blocker.start()
    #expect(blocker.isMissingLists)
    await h.server.setFailing(false)
    await blocker.refreshIfNeeded()
    #expect(!blocker.isMissingLists)
}

@MainActor @Test func turningASiteBackOnByName() {
    let blocker = Harness().makeBlocker()
    blocker.setBlocking(false, forSiteOf: URL(string: "https://www.example.com/")!)
    #expect(blocker.offSites == ["example.com"])
    blocker.setBlocking(true, forSite: "example.com")
    #expect(blocker.isBlocking(on: URL(string: "https://shop.example.com/")!))
}
