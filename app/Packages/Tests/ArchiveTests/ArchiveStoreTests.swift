import Foundation
import Testing
import Archive
import SelaTestSupport
import SidebarModel

private let day: TimeInterval = 24 * 60 * 60

@MainActor
private func makeStore(_ file: URL? = nil, now: Date = fixtureDate) throws -> (ArchiveStore, URL) {
    let file = try file ?? temporaryFolder().appending(path: "Archive.json")
    return (ArchiveStore(fileURL: file, now: { now }), file)
}

private func entry(_ name: String, at date: Date = fixtureDate, title: String? = nil) -> ArchiveEntry {
    ArchiveEntry(id: UUID(), url: URL(string: "https://\(name).example.com/"), title: title ?? name, spaceID: "S", archivedAt: date)
}

@MainActor @Test func addedEntriesComeNewestFirst() throws {
    let (store, _) = try makeStore()
    store.add([entry("a", at: fixtureDate.addingTimeInterval(-20))])
    store.add([entry("b", at: fixtureDate.addingTimeInterval(-10)), entry("c", at: fixtureDate.addingTimeInterval(-30))])
    #expect(store.entries.map(\.title) == ["b", "a", "c"])
}

@MainActor @Test func entriesSurviveReload() throws {
    let (store, file) = try makeStore()
    store.add([entry("a")])
    let (reloaded, _) = try makeStore(file)
    #expect(reloaded.entries == store.entries)
}

@MainActor @Test func oldEntriesArePruned() throws {
    let (store, _) = try makeStore()
    store.add([entry("old", at: fixtureDate.addingTimeInterval(-31 * day)), entry("recent", at: fixtureDate.addingTimeInterval(-29 * day))])
    #expect(store.entries.map(\.title) == ["recent"])
}

@MainActor @Test func atMostOneThousandEntries() throws {
    let (store, _) = try makeStore()
    store.add((0..<1005).map { entry("e\($0)", at: fixtureDate.addingTimeInterval(-Double($0))) })
    #expect(store.entries.count == 1000)
    #expect(store.entries.first?.title == "e0")
    #expect(store.entries.last?.title == "e999")
}

@MainActor @Test func removeReturnsTheEntry() throws {
    let (store, _) = try makeStore()
    let a = entry("a")
    store.add([a])
    #expect(store.remove(a.id) == a)
    #expect(store.entries.isEmpty)
    #expect(store.remove(a.id) == nil)
}

@MainActor @Test func searchMatchesEveryWord() throws {
    let (store, _) = try makeStore()
    store.add([entry("docs", title: "Swift Docs – Apple"), entry("forums", title: "Swift Forums")])
    #expect(store.search("swift docs").map(\.title) == ["Swift Docs – Apple"])
    #expect(store.search("  ").count == 2)
}

@MainActor @Test func corruptFileIsMovedAside() throws {
    let folder = try temporaryFolder()
    let file = folder.appending(path: "Archive.json")
    try Data("{ nope".utf8).write(to: file)
    let (store, _) = try makeStore(file)
    #expect(store.entries.isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(names.contains { $0.hasPrefix("Archive.corrupt-") })
}

@MainActor @Test func entriesWithoutAReasonLoadAsClosed() throws {
    let file = try temporaryFolder().appending(path: "Archive.json")
    let json = #"[{"archivedAt": \#(fixtureDate.timeIntervalSince1970), "id": "\#(UUID().uuidString)", "title": "Old"}]"#
    try Data(json.utf8).write(to: file)
    let (store, _) = try makeStore(file)
    #expect(store.entries.map(\.reason) == [.closed])
}

@MainActor @Test func searchIgnoresCaseAndAccents() throws {
    let (store, _) = try makeStore()
    store.add([entry("a", title: "Über uns")])
    #expect(store.search("über").count == 1)
    #expect(store.search("uber").count == 1)
}
