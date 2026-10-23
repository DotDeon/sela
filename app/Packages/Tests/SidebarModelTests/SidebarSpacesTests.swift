import Foundation
import Testing
@testable import SidebarModel

@Test func addSpaceCreatesContainers() throws {
    var doc = fixtureDocument()
    let id = doc.addSpace(title: "Work", icon: "💼", now: fixtureDate)
    #expect(doc.spaces.count == 2)
    let space = try #require(doc.space(id))
    #expect(space.title == "Work")
    #expect(space.icon == "💼")
    #expect(doc.item(space.pinnedContainerID)?.kind == .container(.pinned(id)))
    #expect(doc.item(space.unpinnedContainerID)?.kind == .container(.unpinned(id)))
    try doc.validate()
}

@Test func removeSpaceRemovesEverythingUnderIt() throws {
    var doc = fixtureDocument()
    let other = doc.addSpace(title: nil, icon: nil, now: fixtureDate)
    try doc.insert(fixtureTab("o1", parent: doc.space(other)!.pinnedContainerID), into: doc.space(other)!.pinnedContainerID, at: nil)
    let removed = try doc.removeSpace("S")
    #expect(Set(removed.map(\.id)) == ["P", "U", "folder", "sub", "t1", "t2", "t3"])
    #expect(doc.spaces.map(\.id) == [other])
    #expect(doc.item("o1") != nil)
    #expect(doc.item("f1") != nil)
    try doc.validate()
}

@Test func removingLastSpaceThrows() {
    var doc = fixtureDocument()
    let before = doc
    #expect(throws: SidebarError.cannotRemoveLastSpace) {
        try doc.removeSpace("S")
    }
    #expect(doc == before)
}

@Test func removeUnknownSpaceThrows() {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.spaceNotFound("nope")) {
        try doc.removeSpace("nope")
    }
}

@Test func moveSpaceReorders() throws {
    var doc = fixtureDocument()
    let second = doc.addSpace(title: nil, icon: nil, now: fixtureDate)
    let third = doc.addSpace(title: nil, icon: nil, now: fixtureDate)
    try doc.moveSpace(third, to: 0)
    #expect(doc.spaces.map(\.id) == [third, "S", second])
    try doc.moveSpace(third, to: 99)
    #expect(doc.spaces.map(\.id) == ["S", second, third])
}

@Test func updateSpaceSetsDetails() throws {
    var doc = fixtureDocument()
    let theme = SpaceTheme(primary: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
    try doc.updateSpace("S", title: "Home", icon: "house", theme: theme)
    let space = try #require(doc.space("S"))
    #expect(space.title == "Home")
    #expect(space.icon == "house")
    #expect(space.theme == theme)
    #expect(space.pinnedContainerID == "P")
    #expect(space.unpinnedContainerID == "U")
}

@Test func setTitleAndExpanded() throws {
    var doc = fixtureDocument()
    try doc.setTitle("t1", "Mail")
    try doc.setExpanded("folder", true)
    #expect(doc.item("t1")?.title == "Mail")
    #expect(doc.item("folder")?.kind == .folder(FolderInfo(icon: nil, isExpanded: true)))
}

@Test func setExpandedRejectsTabs() {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.notAFolder("t1")) {
        try doc.setExpanded("t1", true)
    }
}

@Test func updateTabRejectsFolders() {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.notATab("folder")) {
        try doc.updateTab("folder") { $0.isMuted = true }
    }
}

@Test func updateTabChangesInfo() throws {
    var doc = fixtureDocument()
    try doc.updateTab("t1") { $0.savedTitle = "One" }
    guard case .tab(let info) = doc.item("t1")?.kind else { Issue.record("not a tab"); return }
    #expect(info.savedTitle == "One")
}
