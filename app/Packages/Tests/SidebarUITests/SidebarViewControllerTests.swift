import AppKit
import Foundation
import Testing
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Favicons
import Sidebar
import SidebarModel
@testable import SidebarUI

private struct Offline: Error {}

/// Polls every 10 ms for up to 2 seconds.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

@MainActor
private struct Harness {
    let model: BrowserWindowModel
    let controller: SidebarViewController

    let window: NSWindow

    init(document: SidebarDocument = fixtureDocument(), zoomStore: PageZoomStore = PageZoomStore()) throws {
        let folder = try temporaryFolder()
        let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { document })
        model = BrowserWindowModel(engine: FakeEngine(), sidebar: store, zoomStore: zoomStore)
        let favicons = FaviconStore(cacheFolder: folder, fetch: { _ in throw Offline() })
        controller = SidebarViewController(model: model, favicons: favicons)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()
    }

    var firstOutline: SidebarOutlineView { controller.pager.pages[0].outlineView }
}

@MainActor @Test func showsOnePagePerSpace() throws {
    let h = try Harness()
    #expect(h.controller.pager.pages.count == 2)
}

@MainActor @Test func outlineShowsPinnedDividerUnpinned() throws {
    let h = try Harness()
    // fold, p2 (fold is expanded), p1, divider, u1, u2
    #expect(h.firstOutline.numberOfRows == 6)
}

@MainActor @Test func selectingSpaceScrollsPager() async throws {
    let h = try Harness()
    h.model.selectSpace("S2")
    try await eventually { h.controller.pager.currentPage == 1 }
}

@MainActor @Test func newTabAppearsAnimatedNotReloaded() async throws {
    let h = try Harness()
    let reloads = h.firstOutline.reloadCount
    h.model.newTab(url: URL(string: "https://new.example.com/"))
    try await eventually { h.firstOutline.numberOfRows == 7 }
    #expect(h.firstOutline.reloadCount == reloads)
}

@MainActor @Test func favoritesGridShowsFavorites() throws {
    let h = try Harness()
    #expect(h.controller.favoritesGrid.collectionView.numberOfItems(inSection: 0) == 1)
}

@MainActor @Test func selectedTabRowIsSelected() async throws {
    let h = try Harness()
    h.model.select("u1")
    try await eventually { h.firstOutline.selectedRow == 4 }
}

@MainActor @Test func renameIsNotOverwrittenByOtherChanges() async throws {
    let h = try Harness()
    h.controller.pager.pages[0].beginRenaming("p1")
    let cell = try #require(h.firstOutline.view(atColumn: 0, row: 2, makeIfNecessary: false) as? ItemCellView)
    #expect(cell.titleField.isEditable)
    cell.titleField.stringValue = "Typed"
    h.model.sidebar.markActive("u1", at: Date())
    try await Task.sleep(for: .milliseconds(100))
    #expect(cell.titleField.stringValue == "Typed")
}

@MainActor @Test func everyExpandedFolderOpensAtLaunch() throws {
    let tab = { (id: ItemID, parent: ItemID) in fixtureTab(id, parent: parent) }
    let folder = { (id: ItemID, children: [ItemID]) in
        fixtureItem(id, parent: "P", children: children, kind: .folder(FolderInfo(icon: nil, isExpanded: true)))
    }
    let items = [
        fixtureItem("F", parent: nil, kind: .container(.favorites)),
        fixtureItem("P", parent: nil, children: ["fa", "fb", "fc"], kind: .container(.pinned("S"))),
        folder("fa", ["a1", "a2", "a3"]),
        tab("a1", "fa"), tab("a2", "fa"), tab("a3", "fa"),
        folder("fb", ["b1", "b2", "b3"]),
        tab("b1", "fb"), tab("b2", "fb"), tab("b3", "fb"),
        folder("fc", ["c1"]),
        tab("c1", "fc"),
        fixtureItem("U", parent: nil, kind: .container(.unpinned("S"))),
    ]
    let space = Space(id: "S", title: nil, icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "U")
    let h = try Harness(document: SidebarDocument(version: 1, spaces: [space], favoritesContainerID: "F", items: items))
    // fa, a1, a2, a3, fb, b1, b2, b3, fc, c1, divider
    #expect(h.firstOutline.numberOfRows == 11)
}

@MainActor @Test func newTabButtonCanOpenSomethingElse() throws {
    let h = try Harness()
    let before = h.model.sidebar.document
    var clicked = 0
    h.controller.onNewTabClicked = { clicked += 1 }
    h.controller.pager.onNewTab?()
    #expect(clicked == 1)
    #expect(h.model.sidebar.document == before)
}

@MainActor @Test func aSplitShowsOneRowWithASegmentPerPane() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    // fold, p2, p1, divider, split
    (h.model.liveTab(for: "u1") as? FakeTab)?.finishLoading(title: "One")
    (h.model.liveTab(for: "u2") as? FakeTab)?.finishLoading(title: "Two")
    try await eventually { h.firstOutline.numberOfRows == 5 }
    let cell = try #require(h.firstOutline.view(atColumn: 0, row: 4, makeIfNecessary: true) as? SplitCellView)
    try await eventually { cell.segmentTitles == ["One", "Two"] }
}

@MainActor @Test func clickingASegmentSelectsThatPane() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    try await eventually { h.firstOutline.numberOfRows == 5 }
    h.model.select("u2")
    let cell = try #require(h.firstOutline.view(atColumn: 0, row: 4, makeIfNecessary: true) as? SplitCellView)
    cell.selectSegment(0)
    #expect(h.model.selectedItemID == "u1")
}

@MainActor @Test func tabMenuOffersOpenInSplitView() throws {
    let h = try Harness()
    h.model.select("u2")
    let page = h.controller.pager.pages[0]
    let item = try #require(page.menuItems(for: "u1").first { $0.title == "Open in Split View" })
    #expect(item.isEnabled)
    #expect(page.menuItems(for: "u2").first { $0.title == "Open in Split View" }?.isEnabled == false)
    #expect(page.menuItems(for: "f1").first { $0.title == "Open in Split View" }?.isEnabled != true)
    h.model.select("f1")
    #expect(page.menuItems(for: "u1").first { $0.title == "Open in Split View" }?.isEnabled == false)
}

@MainActor @Test func splitMenuSeparatesAndCloses() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    let split = try #require(h.model.selectedSplit?.id)
    let page = h.controller.pager.pages[0]
    let titles = page.menuItems(for: split).map(\.title)
    #expect(titles.contains("Separate Split View"))
    #expect(titles.contains("Close Split View"))
}

@MainActor @Test func theSplitRowIsSelectedWhenAPaneIs() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    // fold, p2, p1, divider, split
    try await eventually { h.firstOutline.numberOfRows == 5 && h.firstOutline.selectedRow == 4 }
}

@MainActor @Test func openInSplitIsOffAcrossSections() throws {
    let h = try Harness()
    h.model.select("u2")
    let page = h.controller.pager.pages[0]
    #expect(page.menuItems(for: "p1").first { $0.title == "Open in Split View" }?.isEnabled == false)
}

@MainActor @Test func pinnedTabsCanBeDeleted() throws {
    let h = try Harness()
    let page = h.controller.pager.pages[0]
    #expect(page.menuItems(for: "p1").contains { $0.title == "Delete" })
    #expect(!page.menuItems(for: "u1").contains { $0.title == "Delete" })
}

@MainActor @Test func pinnedRowsOfferCloseOnlyWhileLoaded() async throws {
    let h = try Harness()
    // fold, p2, p1
    let cell = try #require(h.firstOutline.view(atColumn: 0, row: 2, makeIfNecessary: true) as? ItemCellView)
    #expect(!cell.showsCloseOnHover)
    h.model.select("p1")
    try await eventually { cell.showsCloseOnHover }
    let unpinned = try #require(h.firstOutline.view(atColumn: 0, row: 4, makeIfNecessary: true) as? ItemCellView)
    #expect(unpinned.showsCloseOnHover)
}

@MainActor
private func fakeExtension(named name: String) async throws -> FakeExtension {
    let folder = try temporaryFolder()
    try JSONSerialization.data(withJSONObject: ["name": name, "version": "1"]).write(to: folder.appending(path: "manifest.json"))
    return try #require(try await FakeEngine().loadExtension(id: name, at: folder, permissions: .none) as? FakeExtension)
}

@MainActor @Test func extensionsGetButtonsAndClicksReachTheWindow() async throws {
    let h = try Harness()
    let darkReader = try await fakeExtension(named: "dark-reader")
    var clicked: [String] = []
    h.controller.onExtensionClicked = { item, _ in clicked.append(item.id) }
    h.controller.extensions = [darkReader]
    try await eventually { h.controller.extensionAnchor(for: "dark-reader") is ExtensionButton }
    let button = try #require(h.controller.extensionAnchor(for: "dark-reader") as? ExtensionButton)
    button.performClick(nil)
    #expect(clicked == ["dark-reader"])
}

@MainActor @Test func extensionBadgesFollowTheExtension() async throws {
    let h = try Harness()
    let blocker = try await fakeExtension(named: "blocker")
    h.controller.extensions = [blocker]
    try await eventually { h.controller.extensionAnchor(for: "blocker") is ExtensionButton }
    blocker.actionState = ExtensionActionState(label: "Blocker", badgeText: "12", icon: nil, isEnabled: false)
    let button = try #require(h.controller.extensionAnchor(for: "blocker") as? ExtensionButton)
    try await eventually { !button.isEnabled }
    #expect(button.toolTip == "Blocker")
}

@MainActor @Test func anExtensionWithoutAButtonUsesTheMenu() async throws {
    let h = try Harness()
    let quiet = try await fakeExtension(named: "quiet")
    quiet.actionState = nil
    h.controller.extensions = [quiet]
    h.controller.view.layoutSubtreeIfNeeded()
    #expect(!(h.controller.extensionAnchor(for: "quiet") is ExtensionButton))
}

@MainActor @Test func theSpaceMenuChoosesAProfile() throws {
    let h = try Harness()
    let work = h.model.sidebar.addProfile(name: "Work")
    let profiles = try #require(h.controller.spaceBar.spaceMenu(for: "S").items.first { $0.title == "Profile" }?.submenu)
    #expect(profiles.items.map(\.title) == ["Default", "Work", "", "New Profile…"])
    #expect(profiles.items[0].state == .on)
    #expect(profiles.items[1].state == .off)

    let choice = profiles.items[1]
    _ = (choice.target as? NSObject)?.perform(choice.action)
    #expect(h.model.sidebar.document.profileID(of: "S") == work)
    let updated = try #require(h.controller.spaceBar.spaceMenu(for: "S").items.first { $0.title == "Profile" }?.submenu)
    #expect(updated.items[1].state == .on)
}

@MainActor @Test func readerButtonShowsForArticlesAndToggles() async throws {
    let h = try Harness()
    h.model.select("u1")
    let tab = try #require(h.model.liveTab(for: "u1") as? FakeTab)
    try await eventually { h.controller.readerButton.isHidden }
    tab.simulateArticle(true)
    try await eventually { !h.controller.readerButton.isHidden }
    h.controller.readerButton.performClick(nil)
    try await eventually { tab.state.isShowingReader }
    try await eventually { h.controller.readerButton.accessibilityLabel() == "Hide Reader" }
}

@MainActor @Test func zoomLevelShowsInTheAddressUntilClicked() async throws {
    let h = try Harness(zoomStore: PageZoomStore(defaults: UserDefaults(suiteName: "sela-zoom-\(UUID().uuidString)")!))
    h.model.select("u1")
    try await eventually { h.controller.zoomButton.isHidden }
    h.model.zoomIn()
    h.model.zoomIn()
    try await eventually { !h.controller.zoomButton.isHidden && h.controller.zoomButton.title == "125%" }
    h.controller.zoomButton.performClick(nil)
    #expect(h.model.selectedTab?.state.pageZoom == 1)
    try await eventually { h.controller.zoomButton.isHidden }
}

@MainActor @Test func clearShowsOnlyWhileThereAreUnpinnedTabs() async throws {
    let empty = SidebarDocument(version: SidebarDocument.currentVersion, spaces: [
        Space(id: "S", title: nil, icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "U"),
    ], favoritesContainerID: "F", items: [
        fixtureItem("F", parent: nil, kind: .container(.favorites)),
        fixtureItem("P", parent: nil, kind: .container(.pinned("S"))),
        fixtureItem("U", parent: nil, kind: .container(.unpinned("S"))),
    ])
    let h = try Harness(document: empty)
    func divider() -> DividerCellView? {
        (0..<h.firstOutline.numberOfRows).lazy
            .compactMap { h.firstOutline.view(atColumn: 0, row: $0, makeIfNecessary: true) as? DividerCellView }
            .first
    }
    #expect(divider()?.isClearVisible == false)
    h.model.newTab(url: URL(string: "https://new.example.com/"))
    try await eventually { divider()?.isClearVisible == true }
}
