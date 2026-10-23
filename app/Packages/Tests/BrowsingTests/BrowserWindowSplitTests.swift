import Foundation
import Testing
import Archive
import BrowTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

@MainActor
private final class Clock {
    var now = fixtureDate.addingTimeInterval(100)
    func read() -> Date {
        now = now.addingTimeInterval(1)
        return now
    }
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let clock = Clock()
    let store: SidebarStore
    let archive: ArchiveStore
    let model: BrowserWindowModel

    init(prepare: (SidebarStore) -> Void = { _ in }) throws {
        let folder = try temporaryFolder()
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        prepare(store)
        let clock = clock
        archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { clock.now })
        model = BrowserWindowModel(engine: engine, sidebar: store, archive: archive, now: { clock.read() })
    }

    func live(_ id: ItemID) -> FakeTab? { model.liveTab(for: id) as? FakeTab }
    var unpinned: [ItemID] { store.document.item("U")?.childIDs ?? [] }
}

@MainActor @Test func addSplitPaneMakesASplitWithANewBlankTab() throws {
    let h = try Harness()
    h.model.select("u1")
    let n = try #require(h.model.addSplitPane())
    #expect(h.model.selectedItemID == n)
    #expect(h.model.selectedSplit?.paneIDs == ["u1", n])
    #expect(h.live(n)?.loadedURLs == [])
}

@MainActor @Test func addSplitPaneRefusesFavourites() throws {
    let h = try Harness()
    h.model.select("f1")
    let before = h.store.document
    #expect(h.model.addSplitPane() == nil)
    #expect(h.store.document == before)
}

@MainActor @Test func addSplitPaneRefusesAFullSplit() throws {
    let h = try Harness()
    h.model.select("u1")
    for _ in 0..<3 { h.model.addSplitPane() }
    #expect(h.model.selectedSplit?.paneIDs.count == 4)
    let before = h.store.document
    #expect(h.model.addSplitPane() == nil)
    #expect(h.store.document == before)
}

@MainActor @Test func selectingASplitLoadsEveryPane() throws {
    var splitID: ItemID?
    let h = try Harness { splitID = $0.addToSplit("u1", with: "p1") }
    let s = try #require(splitID)
    h.model.select(s)
    #expect(h.model.selectedItemID == "u1")
    #expect(h.live("p1") != nil)
    #expect(h.live("u1") != nil)
}

@MainActor @Test func selectingTheSplitRowPicksTheLastUsedPane() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.select("u2")
    h.model.openInSplit("u1")
    let s = try #require(h.model.selectedSplit?.id)
    #expect(h.model.selectedSplit?.paneIDs == ["u2", "u1"])
    h.model.select("p1")
    #expect(h.model.selectedSplit == nil)
    h.model.select(s)
    #expect(h.model.selectedItemID == "u1")
}

@MainActor @Test func closingAPaneSelectsItsNeighbour() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    let n = try #require(h.model.addSplitPane())
    h.model.select("u2")
    #expect(h.model.selectedSplit?.paneIDs == ["u1", "u2", n])
    h.model.close("u2")
    #expect(h.model.selectedItemID == n)
    #expect(h.model.selectedSplit?.paneIDs == ["u1", n])
}

@MainActor @Test func closingTheSecondLastPaneLeavesAPlainTab() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    h.model.close("u2")
    #expect(h.model.selectedSplit == nil)
    #expect(h.model.selectedItemID == "u1")
    #expect(h.unpinned.first == "u1")
}

@MainActor @Test func closeSplitArchivesUnpinnedPanes() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    let s = try #require(h.model.selectedSplit?.id)
    h.model.closeSplit(s)
    #expect(h.archive.entries.count == 2)
    #expect(h.store.document.item("u1") == nil)
    #expect(h.store.document.item("u2") == nil)
    #expect(h.store.document.item(s) == nil)
}

@MainActor @Test func rotateAndResize() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    h.model.rotateSelectedSplit()
    h.model.resizeSelectedSplit([0.3, 0.7])
    #expect(h.model.selectedSplit?.orientation == .vertical)
    #expect(h.model.selectedSplit?.fractions == [0.3, 0.7])
}

@MainActor @Test func separatingKeepsTheSelectedTab() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    h.model.separateSelectedSplit()
    #expect(h.model.selectedSplit == nil)
    #expect(h.model.selectedItemID == "u2")
    #expect(h.unpinned == ["u1", "u2"])
}

@MainActor @Test func closingAPinnedPaneTakesItOutOfTheSplit() throws {
    let h = try Harness()
    h.model.select("p1")
    let n = try #require(h.model.addSplitPane())
    h.model.select("p1")
    h.model.close("p1")
    #expect(h.model.selectedItemID == n)
    #expect(h.live("p1") == nil)
    #expect(h.model.selectedSplit == nil)
    #expect(h.store.document.item("p1")?.parentID == "P")
}

@MainActor @Test func closeSplitOnAPinnedSplitUnloadsEveryPane() throws {
    let h = try Harness()
    h.model.select("p1")
    let n = try #require(h.model.addSplitPane())
    let s = try #require(h.model.selectedSplit?.id)
    h.model.closeSplit(s)
    #expect(h.live("p1") == nil)
    #expect(h.live(n) == nil)
    #expect(h.store.document.item("p1") != nil)
}

@MainActor @Test func openInSplitKeepsPinnedAndUnpinnedApart() throws {
    let h = try Harness()
    h.model.select("u1")
    #expect(!h.model.canOpenInSplit("p1"))
    h.model.openInSplit("p1")
    #expect(h.model.selectedSplit == nil)
    #expect(h.store.document.item("p1")?.parentID == "P")
    #expect(h.model.canOpenInSplit("u2"))
}
