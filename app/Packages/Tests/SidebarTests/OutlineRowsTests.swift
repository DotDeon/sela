import Foundation
import Testing
import Sidebar
import SidebarModel

private let space = fixtureDocument().space("S")!

@Test func rootRowsHaveDividerBetweenSections() {
    #expect(rootRows(for: space, in: fixtureDocument()) == [.item("fold"), .item("p1"), .divider, .item("u1"), .item("u2")])
}

@Test func childRowsOfFolder() {
    #expect(childRows(of: "fold", in: fixtureDocument()) == [.item("p2")])
}

@Test func snapshotIncludesExpandedFolders() {
    let snapshot = outlineSnapshot(for: space, in: fixtureDocument())
    #expect(snapshot[nil] == rootRows(for: space, in: fixtureDocument()))
    #expect(snapshot[.item("fold")] == [.item("p2")])
    #expect(snapshot.count == 2)
}

@Test func snapshotSkipsCollapsedFolders() throws {
    var doc = fixtureDocument()
    try doc.setExpanded("fold", false)
    let snapshot = outlineSnapshot(for: space, in: doc)
    #expect(snapshot[.item("fold")] == nil)
    #expect(snapshot.count == 1)
}

@Test(arguments: [
    (nil as OutlineRow?, 0, "P", 0 as Int?),
    (nil, 2, "P", 2),
    (nil, 3, "U", 0),
    (nil, 4, "U", 1),
    (nil, 5, "U", 2),
    (.item("fold"), -1, "fold", nil),
    (.item("fold"), 0, "fold", 0),
] as [(OutlineRow?, Int, ItemID, Int?)])
func dropDestinations(parent: OutlineRow?, childIndex: Int, expectedParent: ItemID, expectedIndex: Int?) throws {
    let destination = try #require(dropDestination(parent: parent, childIndex: childIndex, space: space, document: fixtureDocument()))
    #expect(destination.parent == expectedParent)
    #expect(destination.index == expectedIndex)
}

@Test func dropOnTabOrDividerIsRefused() {
    let doc = fixtureDocument()
    #expect(dropDestination(parent: .item("p1"), childIndex: -1, space: space, document: doc) == nil)
    #expect(dropDestination(parent: .item("p1"), childIndex: 0, space: space, document: doc) == nil)
    #expect(dropDestination(parent: .divider, childIndex: 0, space: space, document: doc) == nil)
    #expect(dropDestination(parent: nil, childIndex: -1, space: space, document: doc) == nil)
}

@Test func spacesWithoutThemeCycleThroughDefaults() {
    #expect(defaultSpaceColors.count == 8)
    #expect(themeColor(for: space, at: 9) == defaultSpaceColors[1])
    var themed = space
    let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    themed.theme = SpaceTheme(primary: red)
    #expect(themeColor(for: themed, at: 0) == red)
}
