import Foundation
import Testing
import Archive
import BrowTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

private func url(_ name: String) -> URL { URL(string: "https://\(name).example.com/")! }

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let store: SidebarStore
    let archive: ArchiveStore
    let model: BrowserWindowModel

    init() throws {
        let folder = try temporaryFolder()
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { fixtureDate })
        model = BrowserWindowModel(engine: engine, sidebar: store, archive: archive, now: { fixtureDate })
    }

    func live(_ id: ItemID) -> FakeTab? { model.liveTab(for: id) as? FakeTab }
    var unpinned: [ItemID] { store.document.item("U")?.childIDs ?? [] }
}

@MainActor @Test func closingUnpinnedArchivesIt() throws {
    let h = try Harness()
    h.model.close("u1")
    let entry = try #require(h.archive.entries.first)
    #expect(entry.url == url("u1"))
    #expect(entry.title == "u1 title")
    #expect(entry.spaceID == "S")
}

@MainActor @Test func closingPinnedDoesNotArchive() throws {
    let h = try Harness()
    h.model.select("p1")
    h.model.close("p1")
    #expect(h.archive.entries.isEmpty)
}

@MainActor @Test func clearArchivesEveryUnpinnedTab() throws {
    let h = try Harness()
    h.model.clearUnpinned()
    #expect(h.archive.entries.count == 2)
}

@MainActor @Test func archiveUsesTheLivePage() throws {
    let h = try Harness()
    h.model.select("u1")
    let tab = try #require(h.live("u1"))
    tab.load(url("other"))
    tab.finishLoading(title: "Other")
    h.model.close("u1")
    #expect(h.archive.entries.first?.url == url("other"))
    #expect(h.archive.entries.first?.title == "Other")
}

@MainActor @Test func restoreReopensAtTopOfItsSpace() throws {
    let h = try Harness()
    h.model.close("u1")
    let entry = try #require(h.archive.entries.first)
    h.model.restore(entry.id)
    let restored = try #require(h.unpinned.first)
    #expect(h.unpinned == [restored, "u2"])
    #expect(h.model.selectedItemID == restored)
    #expect(h.live(restored)?.loadedURLs == [url("u1")])
    #expect(h.archive.entries.isEmpty)
}

@MainActor @Test func restoreIntoDeletedSpaceUsesCurrent() throws {
    let h = try Harness()
    let entry = ArchiveEntry(id: UUID(), url: url("gone"), title: "Gone", spaceID: "S2", archivedAt: fixtureDate)
    h.archive.add([entry])
    try h.store.removeSpace("S2")
    h.model.reconcile()
    h.model.restore(entry.id)
    #expect(h.model.selectedSpaceID == "S")
    #expect(h.live(h.unpinned[0])?.loadedURLs == [url("gone")])
}

@MainActor @Test func reopenLastArchivedRestoresNewest() throws {
    let h = try Harness()
    h.model.close("u1")
    h.model.reopenLastArchived()
    #expect(h.live(h.unpinned[0])?.loadedURLs == [url("u1")])
}

@MainActor @Test func reopenWithEmptyArchiveDoesNothing() throws {
    let h = try Harness()
    let before = h.store.document
    h.model.reopenLastArchived()
    #expect(h.store.document == before)
}

@MainActor @Test func visitsAreReportedOncePerPage() throws {
    let h = try Harness()
    var visits: [(URL, String?)] = []
    h.model.onPageVisited = { visits.append(($0, $1)) }
    h.model.select("u1")
    let tab = try #require(h.live("u1"))
    tab.finishLoading(title: "A")
    #expect(visits.map(\.0) == [url("u1")])
    #expect(visits.first?.1 == "A")
    tab.finishLoading(title: "A", faviconURL: url("icon"))
    #expect(visits.count == 1)
    tab.load(url("b"))
    tab.finishLoading(title: "B")
    #expect(visits.map(\.0) == [url("u1"), url("b")])
    tab.load(URL(string: "about:blank")!)
    tab.finishLoading(title: nil)
    #expect(visits.count == 2)
}

@MainActor @Test func markSelectionActiveRefreshesTheTabYouAreReading() throws {
    var clock = fixtureDate
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let model = BrowserWindowModel(engine: FakeEngine(), sidebar: store, now: { clock })
    model.select("p1")
    clock = fixtureDate.addingTimeInterval(10 * 60 * 60)
    model.markSelectionActive()
    #expect(tabInfo(store.document, "p1")?.lastActiveAt == clock)
}
