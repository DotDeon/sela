import AppKit
import Foundation
import Testing
import Favicons

private struct FetchFailed: Error {}

/// Serves canned data and records every URL it was asked for.
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URL] = []
    private let respond: @Sendable (URL) throws -> Data

    init(_ respond: @escaping @Sendable (URL) throws -> Data) {
        self.respond = respond
    }

    var fetched: [URL] {
        lock.withLock { requests }
    }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { requests.append(url) }
        return try respond(url)
    }
}

private func png(width: Int = 4) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "brow-favicons-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

private let page = URL(string: "https://a.example.com/some/page")!

@MainActor @Test func missFetchesFaviconICO() async throws {
    let server = FakeServer { _ in png() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    #expect(store.image(forPage: page) == nil)
    try await eventually { store.image(forPage: page) != nil }
    #expect(server.fetched == [URL(string: "https://a.example.com/favicon.ico")!])
}

@MainActor @Test func rememberedIconWins() async throws {
    let icon = URL(string: "https://cdn.example.com/icon.png")!
    let server = FakeServer { url in url == icon ? png(width: 8) : png(width: 2) }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    store.remember(iconURL: icon, forPage: page)
    try await eventually { store.image(forPage: page)?.representations.first?.pixelsWide == 8 }
    #expect(server.fetched == [icon])
}

@MainActor @Test func iconsSurviveRestart() async throws {
    let cache = try folder()
    let first = FaviconStore(cacheFolder: cache, fetch: FakeServer { _ in png() }.fetch)
    _ = first.image(forPage: page)
    try await eventually { first.image(forPage: page) != nil }

    let server = FakeServer { _ in throw FetchFailed() }
    let second = FaviconStore(cacheFolder: cache, fetch: server.fetch)
    #expect(second.image(forPage: page) != nil)
    #expect(server.fetched.isEmpty)
}

@MainActor @Test func failedFetchIsNotRetried() async throws {
    let server = FakeServer { _ in throw FetchFailed() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    _ = store.image(forPage: page)
    try await eventually { server.fetched.count == 1 }
    try await Task.sleep(for: .milliseconds(50))
    #expect(store.image(forPage: page) == nil)
    try await Task.sleep(for: .milliseconds(50))
    #expect(server.fetched.count == 1)
}

@MainActor @Test func nonWebPagesHaveNoIcon() async throws {
    let server = FakeServer { _ in png() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    #expect(store.image(forPage: URL(fileURLWithPath: "/tmp/page.html")) == nil)
    #expect(store.image(forPage: URL(string: "about:blank")) == nil)
    #expect(store.image(forPage: nil) == nil)
    try await Task.sleep(for: .milliseconds(50))
    #expect(server.fetched.isEmpty)
}

@MainActor @Test func oversizedOrInvalidDataIsIgnored() async throws {
    let big = FakeServer { _ in Data(count: 600 * 1024) }
    let bigStore = FaviconStore(cacheFolder: try folder(), fetch: big.fetch)
    _ = bigStore.image(forPage: page)
    try await eventually { big.fetched.count == 1 }
    try await Task.sleep(for: .milliseconds(50))
    #expect(bigStore.image(forPage: page) == nil)

    let junk = FakeServer { _ in Data("not an image".utf8) }
    let junkStore = FaviconStore(cacheFolder: try folder(), fetch: junk.fetch)
    _ = junkStore.image(forPage: page)
    try await eventually { junk.fetched.count == 1 }
    try await Task.sleep(for: .milliseconds(50))
    #expect(junkStore.image(forPage: page) == nil)
}

@MainActor @Test func hostsShareIcons() async throws {
    let server = FakeServer { _ in png() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    _ = store.image(forPage: page)
    _ = store.image(forPage: URL(string: "https://A.example.com/other")!)
    try await eventually { store.image(forPage: URL(string: "https://a.example.com/third")!) != nil }
    #expect(server.fetched.count == 1)
}

@MainActor @Test func rememberingTheSameIconTwiceFetchesOnce() async throws {
    let icon = URL(string: "https://cdn.example.com/icon.png")!
    let server = FakeServer { _ in png() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    store.remember(iconURL: icon, forPage: page)
    try await eventually { store.image(forPage: page) != nil }
    store.remember(iconURL: icon, forPage: page)
    try await Task.sleep(for: .milliseconds(50))
    #expect(server.fetched == [icon])
}

@MainActor @Test func rememberIgnoresNonWebIconAddresses() async throws {
    let server = FakeServer { _ in png() }
    let store = FaviconStore(cacheFolder: try folder(), fetch: server.fetch)
    store.remember(iconURL: URL(fileURLWithPath: "/dev/zero"), forPage: page)
    store.remember(iconURL: URL(string: "ftp://example.com/icon.png")!, forPage: page)
    try await Task.sleep(for: .milliseconds(50))
    #expect(server.fetched.isEmpty)
}

/// A server that sends data forever.
private final class EndlessProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async {
            let chunk = Data(count: 64 * 1024)
            while !self.lock.withLock({ self.stopped }) {
                self.client?.urlProtocol(self, didLoad: chunk)
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    override func stopLoading() {
        lock.withLock { stopped = true }
    }
}

@Test func sessionFetchStopsPastTheSizeLimit() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EndlessProtocol.self]
    let fetch = FaviconStore.sessionFetch(using: URLSession(configuration: configuration))
    let started = Date()
    await #expect(throws: (any Error).self) {
        _ = try await fetch(URL(string: "https://endless.example.com/favicon.ico")!)
    }
    #expect(Date().timeIntervalSince(started) < 5)
}
