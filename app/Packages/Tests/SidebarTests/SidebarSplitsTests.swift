import Foundation
import Testing
import BrowTestSupport
@testable import SidebarModel

private func split(_ doc: SidebarDocument, _ id: ItemID) -> SplitInfo? {
    if case .split(let info) = doc.item(id)?.kind { return info }
    return nil
}

private func extraTab(_ id: ItemID, in doc: inout SidebarDocument, parent: ItemID = "U") throws {
    try doc.insert(fixtureTab(id, parent: parent), into: parent, at: nil)
}

@Test func addingMakesASplitInTheAnchorsPlace() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    #expect(doc.item("U")?.childIDs == [s])
    #expect(doc.item(s)?.childIDs == ["u1", "u2"])
    #expect(doc.item(s)?.kind == .split(SplitInfo(orientation: .horizontal, fractions: [0.5, 0.5])))
    try doc.validate()
}

@Test func addingToASplitGoesAfterTheAnchorAndEvensSizes() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    let again = try doc.addToSplit("p1", with: "u1")
    #expect(again == s)
    #expect(doc.item(s)?.childIDs == ["u1", "p1", "u2"])
    let third = 1.0 / 3
    #expect(split(doc, s)?.fractions == [third, third, third])
    try doc.validate()
}

@Test func aFifthPaneIsRefused() throws {
    var doc = fixtureDocument()
    try extraTab("u3", in: &doc)
    try extraTab("u4", in: &doc)
    try extraTab("u5", in: &doc)
    _ = try doc.addToSplit("u2", with: "u1")
    _ = try doc.addToSplit("u3", with: "u2")
    _ = try doc.addToSplit("u4", with: "u3")
    #expect(throws: SidebarError.self) { try doc.addToSplit("u5", with: "u4") }
    #expect(doc.item("u5")?.parentID == "U")
}

@Test func favouritesCantJoinSplits() throws {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.notAllowedInSplit("f1")) { try doc.addToSplit("f1", with: "u1") }
    #expect(throws: SidebarError.notAllowedInSplit("f1")) { try doc.addToSplit("u1", with: "f1") }
    #expect(doc == fixtureDocument())
}

@Test func foldersCantJoinSplits() throws {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.notAllowedInSplit("fold")) { try doc.addToSplit("fold", with: "u1") }
}

@Test func removingDownToOnePaneDissolvesTheSplit() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    try doc.remove("u1")
    #expect(doc.item("U")?.childIDs == ["u2"])
    #expect(doc.item("u2")?.parentID == "U")
    #expect(doc.item(s) == nil)
    try doc.validate()
}

@Test func removingAPaneOfThreeKeepsTheSplitAndEvensSizes() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    _ = try doc.addToSplit("p1", with: "u2")
    try doc.remove("u2")
    #expect(doc.item(s)?.childIDs == ["u1", "p1"])
    #expect(split(doc, s)?.fractions == [0.5, 0.5])
    try doc.validate()
}

@Test func movingAPaneOutDissolvesTheSplit() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    try doc.move("u2", to: "P", at: 0)
    #expect(doc.item("U")?.childIDs == ["u1"])
    #expect(doc.item("P")?.childIDs.first == "u2")
    #expect(doc.item(s) == nil)
    try doc.validate()
}

@Test func separatingPutsTabsInPlace() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    try doc.separate(s)
    #expect(doc.item("U")?.childIDs == ["u1", "u2"])
    #expect(doc.item(s) == nil)
    try doc.validate()
}

@Test func splitsCantGoInFavourites() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    #expect(throws: SidebarError.self) { try doc.move(s, to: "F", at: nil) }
}

@Test func fractionsAndOrientationCanChange() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    try doc.setSplitFractions(s, [0.3, 0.7])
    try doc.setSplitOrientation(s, .vertical)
    #expect(split(doc, s) == SplitInfo(orientation: .vertical, fractions: [0.3, 0.7]))
    #expect(throws: SidebarError.self) { try doc.setSplitFractions(s, [1]) }
}

@Test func splitIDFindsThePanesSplit() throws {
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    #expect(doc.splitID(containing: "u2") == s)
    #expect(doc.splitID(containing: "p1") == nil)
    #expect(doc.tabIDs(under: "U") == ["u1", "u2"])
}

@Test func validateRejectsBadSplits() throws {
    func document(children: [ItemID], fractions: [Double], extra: [SidebarItem] = []) -> SidebarDocument {
        var items = fixtureDocument().allItems.filter { $0.id != "U" && $0.id != "u1" && $0.id != "u2" }
        items.append(fixtureItem("U", parent: nil, children: ["s"], kind: .container(.unpinned("S"))))
        items.append(fixtureItem("s", parent: "U", children: children, kind: .split(SplitInfo(orientation: .horizontal, fractions: fractions))))
        items += children.filter { $0 != "f" }.map { fixtureTab($0, parent: "s") } + extra
        return SidebarDocument(version: SidebarDocument.currentVersion, spaces: fixtureDocument().spaces, favoritesContainerID: "F", items: items)
    }
    #expect(throws: SidebarError.self) { try document(children: ["u1"], fractions: [1]).validate() }
    let folder = fixtureItem("f", parent: "s", kind: .folder(FolderInfo(icon: nil, isExpanded: true)))
    let withFolder = document(children: ["u1", "f"], fractions: [0.5, 0.5], extra: [folder])
    #expect(throws: SidebarError.self) { try withFolder.validate() }
    #expect(throws: SidebarError.self) { try document(children: ["u1", "u2"], fractions: [1]).validate() }
    try document(children: ["u1", "u2"], fractions: [0.5, 0.5]).validate()
}

@Test func versionOneFilesStillLoad() throws {
    let file = try temporaryFolder().appending(path: "Sidebar.json")
    var doc = fixtureDocument()
    doc.version = 1
    try SidebarDocumentStore(fileURL: file).save(doc)
    #expect(try SidebarDocumentStore(fileURL: file).load(now: fixtureDate) != nil)
}

@Test func splitsSurviveSaveAndLoad() throws {
    let file = try temporaryFolder().appending(path: "Sidebar.json")
    var doc = fixtureDocument()
    let s = try doc.addToSplit("u2", with: "u1")
    try SidebarDocumentStore(fileURL: file).save(doc)
    let loaded = try #require(try SidebarDocumentStore(fileURL: file).load(now: fixtureDate))
    #expect(loaded.item(s) == doc.item(s))
    #expect(SidebarDocument.currentVersion == 2)
}
