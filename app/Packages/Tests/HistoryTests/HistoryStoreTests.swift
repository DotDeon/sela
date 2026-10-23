import Foundation
import Testing
import History

private let day: TimeInterval = 24 * 60 * 60
private let start = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private final class Clock {
    var now = start
    func tick(_ seconds: TimeInterval = 1) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func makeStore(_ file: URL? = nil, clock: Clock = Clock()) throws -> (HistoryStore, URL, Clock) {
    let file = try file ?? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "brow-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "History.sqlite")
    }()
    return (try HistoryStore(fileURL: file, now: { clock.now }), file, clock)
}

private func url(_ string: String) -> URL { URL(string: string)! }

@MainActor @Test func visitsAreCountedAndTitled() throws {
    let (store, _, clock) = try makeStore()
    store.recordVisit(url: url("https://a.example.com/"), title: nil)
    clock.tick()
    store.recordVisit(url: url("https://a.example.com/"), title: "A")
    let entry = try #require(store.search("", limit: 10).first)
    #expect(entry.visitCount == 2)
    #expect(entry.title == "A")
    #expect(entry.lastVisitedAt == clock.now)
}

@MainActor @Test func searchNeedsEveryWord() throws {
    let (store, _, _) = try makeStore()
    store.recordVisit(url: url("https://forums.swift.org/"), title: "Swift Forums")
    store.recordVisit(url: url("https://swift.org/"), title: "Swift")
    #expect(store.search("swift forum", limit: 10).map(\.url) == [url("https://forums.swift.org/")])
}

@MainActor @Test func wildcardsAreLiteral() throws {
    let (store, _, _) = try makeStore()
    store.recordVisit(url: url("https://a.example.com/"), title: "100% done")
    store.recordVisit(url: url("https://b.example.com/"), title: "plain")
    #expect(store.search("100%", limit: 10).map(\.title) == ["100% done"])
    #expect(store.search("_", limit: 10).isEmpty)
}

@MainActor @Test func recentFirstAndLimited() throws {
    let (store, _, clock) = try makeStore()
    for name in ["a", "b", "c"] {
        store.recordVisit(url: url("https://\(name).example.com/"), title: name)
        clock.tick()
    }
    #expect(store.search("", limit: 2).map(\.title) == ["c", "b"])
}

@MainActor @Test func nonWebAddressesAreIgnored() throws {
    let (store, _, _) = try makeStore()
    store.recordVisit(url: URL(fileURLWithPath: "/tmp/page.html"), title: "file")
    store.recordVisit(url: url("about:blank"), title: "blank")
    #expect(store.search("", limit: 10).isEmpty)
}

@MainActor @Test func oldVisitsArePrunedOnOpen() throws {
    let clock = Clock()
    let (store, file, _) = try makeStore(clock: clock)
    store.recordVisit(url: url("https://old.example.com/"), title: "old")
    clock.tick(2 * day)
    store.recordVisit(url: url("https://kept.example.com/"), title: "kept")
    clock.tick(89 * day)
    let (reopened, _, _) = try makeStore(file, clock: clock)
    #expect(reopened.search("", limit: 10).map(\.title) == ["kept"])
}

@MainActor @Test func clearRemovesEverything() throws {
    let (store, _, _) = try makeStore()
    store.recordVisit(url: url("https://a.example.com/"), title: "A")
    store.clear()
    #expect(store.search("", limit: 10).isEmpty)
}

@MainActor @Test func clearLeavesNoTracesInTheFiles() throws {
    let (store, file, _) = try makeStore()
    // Enough visits to fill many database pages, which a plain delete would leave on the free list.
    for index in 0..<500 {
        store.recordVisit(url: url("https://secret-site.example.com/\(index)"), title: "Secret page \(index)")
    }
    store.clear()
    let folder = file.deletingLastPathComponent()
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
        let data = try Data(contentsOf: folder.appending(path: name))
        #expect(data.range(of: Data("secret-site".utf8)) == nil, "found in \(name)")
    }
    // Closing the store would tidy the files itself, so it stays open while they're read.
    withExtendedLifetime(store) {}
}

@MainActor @Test func searchIgnoresCaseAndAccents() throws {
    let (store, _, _) = try makeStore()
    store.recordVisit(url: url("https://a.example.com/"), title: "Über uns")
    #expect(store.search("über", limit: 10).map(\.title) == ["Über uns"])
    #expect(store.search("uber", limit: 10).map(\.title) == ["Über uns"])
    #expect(store.search("ÜBER", limit: 10).map(\.title) == ["Über uns"])
}

@MainActor @Test func historySurvivesReopen() throws {
    let (store, file, clock) = try makeStore()
    store.recordVisit(url: url("https://a.example.com/"), title: "A")
    let (reopened, _, _) = try makeStore(file, clock: clock)
    #expect(reopened.search("a", limit: 10).map(\.title) == ["A"])
}
