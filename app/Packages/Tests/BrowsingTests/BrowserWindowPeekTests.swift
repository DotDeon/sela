import Foundation
import Testing
import Archive
import BrowTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

private let otherSite = URL(string: "https://other.example.org/")!
private let sameSite = URL(string: "https://other.example.com/")!

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let store: SidebarStore
    let model: BrowserWindowModel

    init() throws {
        let folder = try temporaryFolder()
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        let archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { fixtureDate })
        model = BrowserWindowModel(engine: engine, sidebar: store, archive: archive, now: { fixtureDate })
    }

    func live(_ id: ItemID) -> FakeTab? { model.liveTab(for: id) as? FakeTab }
    var peek: FakeTab? { model.peekTab as? FakeTab }

    /// Selects `id` and clicks a link in its page.
    func click(_ url: URL, in id: ItemID, shiftKey: Bool = false) {
        model.select(id)
        live(id)?.simulateLinkClick(to: url, shiftKey: shiftKey)
    }
}

@MainActor @Test func pinnedTabLinkToAnotherSiteOpensPeek() throws {
    let h = try Harness()
    h.model.select("p1")
    let before = h.store.document
    h.live("p1")?.simulateLinkClick(to: otherSite)
    #expect(h.peek?.loadedURLs == [otherSite])
    #expect(h.live("p1")?.loadedURLs == [URL(string: "https://p1.example.com/")!])
    #expect(h.store.document == before)
}

@MainActor @Test func pinnedTabLinkOnTheSameSiteStaysInTheTab() throws {
    let h = try Harness()
    h.click(sameSite, in: "p1")
    #expect(h.model.peekTab == nil)
    #expect(h.live("p1")?.loadedURLs.last == sameSite)
}

@MainActor @Test func favouritesPeekToo() throws {
    let h = try Harness()
    h.click(otherSite, in: "f1")
    #expect(h.peek?.loadedURLs == [otherSite])
}

@MainActor @Test func unpinnedTabsOnlyPeekOnShiftClick() throws {
    let h = try Harness()
    h.click(otherSite, in: "u1")
    #expect(h.model.peekTab == nil)
    h.click(sameSite, in: "u1", shiftKey: true)
    #expect(h.peek?.loadedURLs == [sameSite])
}

@MainActor @Test func aSecondPeekReplacesTheFirst() throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    let first = try #require(h.peek)
    h.live("p1")?.simulateLinkClick(to: URL(string: "https://third.example.net/")!)
    #expect(first.isClosed)
    #expect(h.peek !== first)
}

@MainActor @Test func expandKeepsTheLivePage() throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    let peek = try #require(h.peek)
    let n = try #require(h.model.expandPeek())
    #expect(h.model.liveTab(for: n) === peek)
    #expect(!peek.isClosed)
    #expect(h.store.document.item("U")?.childIDs.first == n)
    #expect(h.model.selectedItemID == n)
    #expect(h.model.peekTab == nil)
}

@MainActor @Test func splitPeekSplitsWithTheSourceTab() throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    #expect(h.model.canSplitPeek)
    h.model.splitPeek()
    let n = try #require(h.model.selectedItemID)
    #expect(h.model.selectedSplit?.paneIDs == ["p1", n])
    #expect(h.model.peekTab == nil)
}

@MainActor @Test func splitPeekFromAFavouriteOnlyExpands() throws {
    let h = try Harness()
    h.click(otherSite, in: "f1")
    #expect(!h.model.canSplitPeek)
    h.model.splitPeek()
    #expect(h.model.selectedSplit == nil)
    #expect(h.model.selectedItemID == h.store.document.item("U")?.childIDs.first)
}

@MainActor @Test func leavingClosesPeek() throws {
    for leave in [{ (m: BrowserWindowModel) in m.select("u1") }, { $0.selectSpace("S2") }, { $0.closeAllLiveTabs() }] {
        let h = try Harness()
        h.click(otherSite, in: "p1")
        let peek = try #require(h.peek)
        leave(h.model)
        #expect(peek.isClosed)
        #expect(h.model.peekTab == nil)
    }
}

@MainActor @Test func peekVisitsCountAsHistory() throws {
    let h = try Harness()
    var visits: [URL] = []
    h.model.onPageVisited = { url, _ in visits.append(url) }
    h.click(otherSite, in: "p1")
    h.peek?.finishLoading(title: "Other")
    #expect(visits == [otherSite])
}

@MainActor @Test func peekDialogsShowFirst() async throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    let peek = try #require(h.peek)
    let answer = Task { await peek.simulateDialog(.alert(message: "Hi")) }
    try await Task.sleep(for: .milliseconds(50))
    let dialog = try #require(h.model.dialogForSelectedTab)
    #expect(dialog.tabID == peek.id)
    h.model.resolveDialog(dialog.id, with: .dismissed)
    _ = await answer.value
}

@MainActor @Test func peekCanCloseItself() throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    h.peek?.simulateRequestClose()
    #expect(h.model.peekTab == nil)
}

@MainActor @Test func linksFromPeekOpenNewTabsInTheSidebar() throws {
    let h = try Harness()
    h.click(otherSite, in: "p1")
    h.peek?.simulateOpen(url: sameSite, disposition: .background)
    #expect(h.store.document.item("U")?.childIDs.count == 3)
    #expect(h.model.peekTab != nil)
}
