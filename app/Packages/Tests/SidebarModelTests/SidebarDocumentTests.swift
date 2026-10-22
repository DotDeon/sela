import Foundation
import Testing
@testable import SidebarModel

private let date = Date(timeIntervalSince1970: 0)

private func item(_ id: ItemID, parent: ItemID?, children: [ItemID] = [], kind: SidebarItem.Kind) -> SidebarItem {
    SidebarItem(id: id, parentID: parent, childIDs: children, title: nil, createdAt: date, isUnread: false, kind: kind)
}

private func tab(_ id: ItemID, parent: ItemID? = nil) -> SidebarItem {
    item(id, parent: parent, kind: .tab(TabInfo(savedURL: URL(string: "https://example.com/"), savedTitle: nil, lastActiveAt: nil, isMuted: false)))
}

private func folder(_ id: ItemID, parent: ItemID, children: [ItemID] = []) -> SidebarItem {
    item(id, parent: parent, children: children, kind: .folder(FolderInfo(icon: nil, isExpanded: true)))
}

/// Space "S" with pinned "P" (folder > sub, t1), unpinned "U" (t2) and favourites "F".
private func makeDocument(items override: [SidebarItem]? = nil, spaces: [Space]? = nil) -> SidebarDocument {
    let items = override ?? [
        item("F", parent: nil, kind: .container(.favorites)),
        item("P", parent: nil, children: ["folder", "t1"], kind: .container(.pinned("S"))),
        item("U", parent: nil, children: ["t2"], kind: .container(.unpinned("S"))),
        folder("folder", parent: "P", children: ["sub"]),
        folder("sub", parent: "folder"),
        tab("t1", parent: "P"),
        tab("t2", parent: "U"),
    ]
    let spaces = spaces ?? [Space(id: "S", title: "Space", icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "U")]
    return SidebarDocument(version: SidebarDocument.currentVersion, spaces: spaces, favoritesContainerID: "F", items: items)
}

@Test func emptyDocumentHasOneSpaceAndFavorites() throws {
    let doc = SidebarDocument.empty(now: date)
    #expect(doc.spaces.count == 1)
    #expect(doc.item(doc.favoritesContainerID)?.kind == .container(.favorites))
    let space = doc.spaces[0]
    #expect(doc.item(space.pinnedContainerID)?.kind == .container(.pinned(space.id)))
    #expect(doc.item(space.unpinnedContainerID)?.kind == .container(.unpinned(space.id)))
    try doc.validate()
}

@Test func insertAtIndexUpdatesParentAndChild() throws {
    var doc = makeDocument()
    try doc.insert(tab("t3"), into: "P", at: 0)
    #expect(doc.item("P")?.childIDs == ["t3", "folder", "t1"])
    #expect(doc.item("t3")?.parentID == "P")
}

@Test func insertWithNilIndexAppends() throws {
    var doc = makeDocument()
    try doc.insert(tab("t3"), into: "P", at: nil)
    #expect(doc.item("P")?.childIDs == ["folder", "t1", "t3"])
}

@Test func insertClampsIndexPastEnd() throws {
    var doc = makeDocument()
    try doc.insert(tab("t3"), into: "P", at: 99)
    #expect(doc.item("P")?.childIDs == ["folder", "t1", "t3"])
}

@Test func insertDuplicateIDThrows() {
    var doc = makeDocument()
    #expect(throws: SidebarError.duplicateItem("t1")) {
        try doc.insert(tab("t1"), into: "U", at: nil)
    }
}

@Test func insertIntoTabThrows() {
    var doc = makeDocument()
    #expect(throws: SidebarError.parentCannotHaveChildren("t1")) {
        try doc.insert(tab("t3"), into: "t1", at: nil)
    }
}

@Test func moveTabBetweenSpacesContainers() throws {
    var doc = makeDocument()
    try doc.move("t1", to: "U", at: 0)
    #expect(doc.item("P")?.childIDs == ["folder"])
    #expect(doc.item("U")?.childIDs == ["t1", "t2"])
    #expect(doc.item("t1")?.parentID == "U")
}

@Test func moveWithinSameParentReorders() throws {
    var doc = makeDocument()
    try doc.move("t1", to: "P", at: 0)
    #expect(doc.item("P")?.childIDs == ["t1", "folder"])
}

@Test func moveFolderIntoOwnDescendantIsRejected() throws {
    var doc = makeDocument()
    let before = doc
    #expect(throws: SidebarError.wouldCreateCycle("folder")) {
        try doc.move("folder", to: "sub", at: nil)
    }
    #expect(doc == before)
}

@Test func moveContainerIsRejected() {
    var doc = makeDocument()
    #expect(throws: SidebarError.cannotMoveContainer("P")) {
        try doc.move("P", to: "U", at: nil)
    }
}

@Test func removeFolderRemovesSubtree() throws {
    var doc = makeDocument()
    let removed = try doc.remove("folder")
    #expect(Set(removed.map(\.id)) == ["folder", "sub"])
    #expect(doc.item("folder") == nil)
    #expect(doc.item("sub") == nil)
    #expect(doc.item("P")?.childIDs == ["t1"])
}

@Test func removeUnknownThrows() {
    var doc = makeDocument()
    #expect(throws: SidebarError.itemNotFound("nope")) {
        try doc.remove("nope")
    }
}

@Test func validateCatchesParentMismatch() {
    var items = makeDocument().allItems
    let index = items.firstIndex { $0.id == "t1" }!
    items[index].parentID = "U"
    let doc = makeDocument(items: items)
    #expect {
        try doc.validate()
    } throws: { error in
        if case SidebarError.integrity = error { return true }
        return false
    }
}

@Test func validateCatchesMissingSpaceContainer() {
    let doc = makeDocument(spaces: [Space(id: "S", title: nil, icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "missing")])
    #expect {
        try doc.validate()
    } throws: { error in
        if case SidebarError.integrity = error { return true }
        return false
    }
}

@Test func roundTripsThroughJSON() throws {
    let doc = makeDocument()
    let data = try JSONEncoder().encode(doc)
    #expect(try JSONDecoder().decode(SidebarDocument.self, from: data) == doc)
}
