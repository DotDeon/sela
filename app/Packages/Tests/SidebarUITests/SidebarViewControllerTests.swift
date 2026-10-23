import AppKit
import Foundation
import Testing
import BrowTestSupport
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

    init() throws {
        let folder = try temporaryFolder()
        let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        model = BrowserWindowModel(engine: FakeEngine(), sidebar: store)
        let favicons = FaviconStore(cacheFolder: folder, fetch: { _ in throw Offline() })
        controller = SidebarViewController(model: model, favicons: favicons)
        controller.view.frame = NSRect(x: 0, y: 0, width: 260, height: 800)
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
