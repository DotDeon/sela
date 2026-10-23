import Foundation
import Testing
import ContentBlocking

private let hour: TimeInterval = 3600
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let list = FilterList(id: "test", title: "Test", url: URL(string: "https://lists.example.com/test.txt")!)
private let goodText = "[Adblock Plus 2.0]\n||ads.example.com^\n"

/// Answers fetches with whatever `next` holds and counts them.
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _next: Result<(Data, Int), Error> = .success((Data(goodText.utf8), 200))
    private var _fetches = 0

    var next: Result<(Data, Int), Error> {
        get { lock.withLock { _next } }
        set { lock.withLock { _next = newValue } }
    }
    var fetches: Int { lock.withLock { _fetches } }

    func fetch(_ url: URL) async throws -> (Data, Int) {
        let result = lock.withLock { _fetches += 1; return _next }
        return try result.get()
    }
}

@MainActor
private final class Clock {
    var now = start
}

@MainActor
private func makeStore(_ server: FakeServer, clock: Clock, folder: URL? = nil) throws -> (FilterListStore, URL) {
    let folder = try folder ?? {
        let url = FileManager.default.temporaryDirectory.appending(path: "brow-lists-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    return (FilterListStore(folder: folder, now: { clock.now }, fetch: { try await server.fetch($0) }), folder)
}

private struct Offline: Error {}

@MainActor @Test func downloadsMissingLists() async throws {
    let server = FakeServer()
    let (store, folder) = try makeStore(server, clock: Clock())
    #expect(store.text(for: list) == nil)
    #expect(await store.refresh([list]))
    #expect(store.text(for: list) == goodText)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "test.txt").path))
}

@MainActor @Test func freshListsAreNotDownloadedAgain() async throws {
    let server = FakeServer()
    let clock = Clock()
    let (store, _) = try makeStore(server, clock: clock)
    await store.refresh([list])
    clock.now = start.addingTimeInterval(23 * hour)
    #expect(await store.refresh([list]) == false)
    #expect(server.fetches == 1)
}

@MainActor @Test func staleListsAreRefreshed() async throws {
    let server = FakeServer()
    let clock = Clock()
    let (store, _) = try makeStore(server, clock: clock)
    await store.refresh([list])
    clock.now = start.addingTimeInterval(25 * hour)
    server.next = .success((Data("[Adblock Plus 2.0]\n||tracker.example.com^\n".utf8), 200))
    #expect(await store.refresh([list]))
    #expect(server.fetches == 2)
    #expect(store.text(for: list)?.contains("tracker") == true)
}

@MainActor @Test func refreshTimesSurviveANewStore() async throws {
    let server = FakeServer()
    let clock = Clock()
    let (store, folder) = try makeStore(server, clock: clock)
    await store.refresh([list])
    clock.now = start.addingTimeInterval(2 * hour)
    let (again, _) = try makeStore(server, clock: clock, folder: folder)
    #expect(await again.refresh([list]) == false)
    #expect(server.fetches == 1)
}

@MainActor @Test(arguments: [
    Result<(Data, Int), Error>.success((Data(goodText.utf8), 503)),
    .success((Data(), 200)),
    .success((Data("<!DOCTYPE html><html><body>Sign in to Wi-Fi</body></html>".utf8), 200)),
    .success((Data("! Title: something else\n||x.example.com^\n".utf8), 200)),
    .failure(Offline()),
])
func badDownloadsKeepTheOldList(bad: Result<(Data, Int), Error>) async throws {
    let server = FakeServer()
    let clock = Clock()
    let (store, _) = try makeStore(server, clock: clock)
    await store.refresh([list])
    clock.now = start.addingTimeInterval(25 * hour)
    server.next = bad
    #expect(await store.refresh([list]) == false)
    #expect(store.text(for: list) == goodText)
}
