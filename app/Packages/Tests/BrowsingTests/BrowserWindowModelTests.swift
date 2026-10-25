import Foundation
import Testing
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

/// Polls every 10 ms for up to 2 seconds.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

private func url(_ name: String) -> URL { URL(string: "https://\(name).example.com/")! }

/// A clock that moves forward a second each time it's read.
@MainActor
private final class Clock {
    private var current = fixtureDate.addingTimeInterval(100)
    func now() -> Date {
        current = current.addingTimeInterval(1)
        return current
    }
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let store: SidebarStore
    let model: BrowserWindowModel

    init() throws {
        let clock = Clock()
        let file = try temporaryFolder().appending(path: "Sidebar.json")
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: file), saveDelay: .seconds(60), now: clock.now, firstRunDocument: { fixtureDocument() })
        model = BrowserWindowModel(engine: engine, sidebar: store, now: clock.now)
    }

    /// Another window on the same sidebar.
    func secondWindow() -> BrowserWindowModel {
        BrowserWindowModel(engine: engine, sidebar: store)
    }

    func live(_ id: ItemID) -> FakeTab? {
        model.liveTab(for: id) as? FakeTab
    }

    var unpinned: [ItemID] { store.document.item("U")?.childIDs ?? [] }
}

@MainActor @Test func launchSelectsMostRecentlyActiveTab() throws {
    let h = try Harness()
    #expect(h.model.selectedSpaceID == "S")
    #expect(h.model.selectedItemID == "u2")
    #expect(h.live("u2") != nil)
    #expect(h.live("u1") == nil)
}

@MainActor @Test func selectingPinnedLoadsSavedURL() throws {
    let h = try Harness()
    h.model.select("p1")
    #expect(h.model.selectedItemID == "p1")
    #expect(h.live("p1")?.loadedURLs == [url("p1")])
}

@MainActor @Test func selectingItemInOtherSpaceSwitchesSpace() throws {
    let h = try Harness()
    h.model.select("q1")
    #expect(h.model.selectedSpaceID == "S2")
}

@MainActor @Test func selectingFavoriteKeepsSpace() throws {
    let h = try Harness()
    h.model.selectSpace("S2")
    h.model.select("f1")
    #expect(h.model.selectedSpaceID == "S2")
    #expect(h.model.selectedItemID == "f1")
}

@MainActor @Test func spacesRememberTheirSelection() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.selectSpace("S2")
    h.model.select("q1")
    h.model.selectSpace("S")
    #expect(h.model.selectedItemID == "u1")
    h.model.selectSpace("S2")
    #expect(h.model.selectedItemID == "q1")
}

@MainActor @Test func selectionMarksTabsActive() throws {
    let h = try Harness()
    h.model.select("p1")
    #expect(tabInfo(h.store.document, "p1")?.lastActiveAt != nil)
    let left = tabInfo(h.store.document, "u2")?.lastActiveAt
    #expect(left != nil && left! > fixtureDate.addingTimeInterval(10))
}

@MainActor @Test func newTabGoesToTopOfUnpinned() throws {
    let h = try Harness()
    let id = h.model.newTab(url: url("new"))
    #expect(h.unpinned == [id, "u1", "u2"])
    #expect(h.model.selectedItemID == id)
    #expect(h.live(id)?.loadedURLs == [url("new")])
}

@MainActor @Test func loadWithoutSelectionMakesATab() throws {
    let h = try Harness()
    h.model.clearUnpinned()
    #expect(h.model.selectedItemID == nil)
    h.model.load(url("typed"))
    #expect(h.unpinned.count == 1)
    #expect(h.model.selectedTab?.state.url == url("typed"))
}

@MainActor @Test func closingUnpinnedRemovesItem() throws {
    let h = try Harness()
    h.model.select("u1")
    let tab = try #require(h.live("u1"))
    h.model.close("u1")
    #expect(h.store.document.item("u1") == nil)
    #expect(tab.isClosed)
}

@MainActor @Test func closingPinnedOnlyUnloads() throws {
    let h = try Harness()
    h.model.select("p1")
    let tab = try #require(h.live("p1"))
    h.model.close("p1")
    #expect(h.store.document.item("p1") != nil)
    #expect(h.live("p1") == nil)
    #expect(tab.isClosed)
}

@MainActor @Test func closingSelectsTabBelowThenAbove() throws {
    let h = try Harness()
    h.model.select("p1")
    h.model.close("p1")
    #expect(h.model.selectedItemID == "u1")
    h.model.select("u2")
    h.model.close("u2")
    #expect(h.model.selectedItemID == "u1")
}

@MainActor @Test func popupFromPinnedGoesToTopOfUnpinned() throws {
    let h = try Harness()
    h.model.select("p1")
    try #require(h.live("p1")).simulateOpen(url: url("x"), disposition: .foreground)
    let popup = h.unpinned[0]
    #expect(h.unpinned == [popup, "u1", "u2"])
    #expect(h.model.selectedItemID == popup)
}

@MainActor @Test func commandClicksStayInReadingOrder() throws {
    let h = try Harness()
    h.model.select("u1")
    let source = try #require(h.live("u1"))
    for name in ["c1", "c2", "c3"] {
        source.simulateOpen(url: url(name), disposition: .background)
    }
    #expect(h.unpinned.count == 5)
    let opened = Array(h.unpinned[1...3])
    #expect(h.unpinned == ["u1"] + opened + ["u2"])
    #expect(h.model.selectedItemID == "u1")

    h.model.select(opened[0])
    h.model.close(opened[0])
    #expect(h.model.selectedItemID == opened[1])
    h.model.close(opened[1])
    #expect(h.model.selectedItemID == opened[2])
    h.model.close(opened[2])
    #expect(h.model.selectedItemID == "u1")
}

@MainActor @Test func popupClosingItselfReturnsToOpener() throws {
    let h = try Harness()
    h.model.select("u1")
    let popup = try #require(h.live("u1")).simulateOpen(url: url("x"), disposition: .foreground)
    let popupItem = h.unpinned[1]
    popup.simulateRequestClose()
    #expect(h.store.document.item(popupItem) == nil)
    #expect(popup.isClosed)
    #expect(h.model.selectedItemID == "u1")
}

@MainActor @Test func unpinnedNavigationIsRecorded() throws {
    let h = try Harness()
    h.model.select("u1")
    let tab = try #require(h.live("u1"))
    tab.load(url("other"))
    tab.finishLoading(title: "Other")
    #expect(tabInfo(h.store.document, "u1")?.savedURL == url("other"))
    #expect(tabInfo(h.store.document, "u1")?.savedTitle == "Other")
}

@MainActor @Test func awayFromSavedURLAndReset() throws {
    let h = try Harness()
    h.model.select("p1")
    let tab = try #require(h.live("p1"))
    #expect(!h.model.isAwayFromSavedURL("p1"))
    tab.load(URL(string: "https://p1.example.com")!)
    #expect(!h.model.isAwayFromSavedURL("p1"))
    tab.load(url("other"))
    #expect(h.model.isAwayFromSavedURL("p1"))
    h.model.resetToSavedURL("p1")
    #expect(tab.loadedURLs.last == url("p1"))
    #expect(!h.model.isAwayFromSavedURL("p1"))
    #expect(!h.model.isAwayFromSavedURL("u1"))
}

@MainActor @Test func togglePinMovesBothWays() throws {
    let h = try Harness()
    h.model.togglePin("u1")
    #expect(h.store.document.item("P")?.childIDs.last == "u1")
    h.model.togglePin("u1")
    #expect(h.unpinned.first == "u1")
}

@MainActor @Test func clearUnpinnedClosesThem() throws {
    let h = try Harness()
    h.model.select("u1")
    let u1 = try #require(h.live("u1"))
    let u2 = try #require(h.live("u2"))
    h.model.clearUnpinned()
    #expect(h.unpinned.isEmpty)
    #expect(u1.isClosed && u2.isClosed)
    #expect(h.model.selectedItemID.map { ["p1", "p2"].contains($0) } ?? true)
}

@MainActor @Test func numberShortcutsCoverFavoritesFirst() throws {
    let h = try Harness()
    h.model.select(number: 1)
    #expect(h.model.selectedItemID == "f1")
    h.model.select(number: 2)
    #expect(h.model.selectedItemID == "p2")
    h.model.select(number: 3)
    #expect(h.model.selectedItemID == "p1")
    h.model.select(number: 9)
    #expect(h.model.selectedItemID == "u2")
    h.model.select(number: 8)
    #expect(h.model.selectedItemID == "u2")
}

@MainActor @Test func nextAndPreviousWrap() throws {
    let h = try Harness()
    h.model.selectNext()
    #expect(h.model.selectedItemID == "f1")
    h.model.selectPrevious()
    #expect(h.model.selectedItemID == "u2")
}

@MainActor @Test func spaceShortcutsAndWrap() throws {
    let h = try Harness()
    h.model.selectSpace(number: 2)
    #expect(h.model.selectedSpaceID == "S2")
    h.model.selectNextSpace()
    #expect(h.model.selectedSpaceID == "S")
    h.model.selectPreviousSpace()
    #expect(h.model.selectedSpaceID == "S2")
    h.model.selectSpace(number: 7)
    #expect(h.model.selectedSpaceID == "S2")
}

@MainActor @Test func reconcileDropsRemovedItems() throws {
    let h = try Harness()
    h.model.select("u1")
    let tab = try #require(h.live("u1"))
    let other = h.secondWindow()
    other.close("u1")
    h.model.reconcile()
    #expect(h.live("u1") == nil)
    #expect(tab.isClosed)
    #expect(h.model.selectedItemID != "u1")
}

@MainActor @Test func reconcileMovesOffDeletedSpace() throws {
    let h = try Harness()
    h.model.select("q1")
    try h.store.removeSpace("S2")
    h.model.reconcile()
    #expect(h.model.selectedSpaceID == "S")
    #expect(h.model.selectedItemID != "q1")
}

@MainActor @Test func closeAllLiveTabsClosesEverything() throws {
    let h = try Harness()
    h.model.select("p1")
    let p1 = try #require(h.live("p1"))
    let u2 = try #require(h.live("u2"))
    h.model.closeAllLiveTabs()
    #expect(p1.isClosed && u2.isClosed)
    #expect(h.model.selectedTab == nil)
}

@MainActor @Test func dialogOnSelectedTabWaitsForAnswer() async throws {
    let h = try Harness()
    let tab = try #require(h.live("u2"))
    let answer = Task { await tab.simulateDialog(.confirm(message: "Leave?")) }
    try await eventually { h.model.dialogForSelectedTab?.dialog == .confirm(message: "Leave?") }
    let pending = try #require(h.model.dialogForSelectedTab)
    h.model.resolveDialog(pending.id, with: .accepted(text: nil))
    #expect(await answer.value == .accepted(text: nil))
    #expect(h.model.dialogForSelectedTab == nil)
}

@MainActor @Test func dialogInBackgroundTabWaitsUntilSelected() async throws {
    let h = try Harness()
    h.model.select("u1")
    let u1 = try #require(h.live("u1"))
    h.model.select("u2")
    let answer = Task { await u1.simulateDialog(.alert(message: "Hi")) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(h.model.dialogForSelectedTab == nil)
    h.model.select("u1")
    try await eventually { h.model.dialogForSelectedTab?.dialog == .alert(message: "Hi") }
    h.model.resolveDialog(h.model.dialogForSelectedTab!.id, with: .dismissed)
    #expect(await answer.value == .dismissed)
}

@MainActor @Test func closingTabDismissesItsDialog() async throws {
    let h = try Harness()
    let tab = try #require(h.live("u2"))
    let answer = Task { await tab.simulateDialog(.prompt(message: "Name?", defaultText: nil)) }
    try await eventually { h.model.dialogForSelectedTab != nil }
    h.model.close("u2")
    #expect(await answer.value == .dismissed)
}

@MainActor @Test func backgroundTabsDontTakeTheSelection() throws {
    let h = try Harness()
    let id = h.model.newTab(url: url("quiet"), selecting: false)
    #expect(h.unpinned.first == id)
    #expect(h.model.selectedItemID == "u2")
    #expect(h.live(id) != nil)
}

@MainActor @Test func liveTabsFollowTheSidebarOrder() throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.select("p1")
    h.model.select("f1")
    let order = h.model.liveTabsInOrder.compactMap { h.model.itemID(for: $0) }
    #expect(order == ["f1", "p1", "u1", "u2"])
    #expect(h.model.isPinned(h.live("p1")!))
    #expect(h.model.isPinned(h.live("f1")!))
    #expect(!h.model.isPinned(h.live("u1")!))
}

@MainActor @Test func newTabOpensInTheSelectedSpace() throws {
    let h = try Harness()
    h.model.selectSpace("S2")
    let id = h.model.newTab(url: url("new"))
    #expect(h.store.document.spaceID(containing: id) == "S2")
    #expect(h.model.selectedSpaceID == "S2")
    let second = h.secondWindow()
    second.selectSpace("S2")
    let other = second.newTab(url: url("other"))
    #expect(h.store.document.spaceID(containing: other) == "S2")
}
