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

    let window: NSWindow

    init(document: SidebarDocument = fixtureDocument()) throws {
        let folder = try temporaryFolder()
        let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { document })
        model = BrowserWindowModel(engine: FakeEngine(), sidebar: store)
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
