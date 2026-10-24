import Foundation
import Testing
import Archive
import SelaTestSupport
import Sidebar
import SidebarModel

private let hour: TimeInterval = 60 * 60
private let now = fixtureDate.addingTimeInterval(13 * hour)

@Test func staleUnpinnedTabsAreDue() {
    let due = inactiveTabs(in: fixtureDocument(), now: now, after: 12 * hour, protecting: [])
    #expect(Set(due) == ["u1", "u2"])
}

@Test func pinnedAndFavoritesAreNeverDue() {
    let due = inactiveTabs(in: fixtureDocument(), now: now.addingTimeInterval(1000 * hour), after: 12 * hour, protecting: [])
    #expect(Set(due) == ["u1", "u2"])
}

@Test func protectedTabsAreNotDue() {
    #expect(inactiveTabs(in: fixtureDocument(), now: now, after: 12 * hour, protecting: ["u2"]) == ["u1"])
}

@Test func neverSelectedTabsCountFromCreation() throws {
    var doc = fixtureDocument()
    let fresh = SidebarItem(id: "fresh", parentID: "U2", childIDs: [], title: nil, createdAt: now.addingTimeInterval(-2 * hour), isUnread: false, kind: .tab(TabInfo(savedURL: nil, savedTitle: nil, lastActiveAt: nil, isMuted: false)))
    let stale = SidebarItem(id: "stale", parentID: "U2", childIDs: [], title: nil, createdAt: now.addingTimeInterval(-13 * hour), isUnread: false, kind: .tab(TabInfo(savedURL: nil, savedTitle: nil, lastActiveAt: nil, isMuted: false)))
    try doc.insert(fresh, into: "U2", at: nil)
    try doc.insert(stale, into: "U2", at: nil)
    let due = inactiveTabs(in: doc, now: now, after: 12 * hour, protecting: ["u1", "u2"])
    #expect(due == ["stale"])
}

@MainActor @Test func archivingMovesTabsIntoTheArchive() throws {
    let folder = try temporaryFolder()
    let sidebar = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { now })
    let archived = archiveInactiveTabs(sidebar: sidebar, archive: archive, now: now, after: 12 * hour, protecting: [])
    #expect(Set(archived) == ["u1", "u2"])
    #expect(sidebar.document.item("u1") == nil)
    #expect(sidebar.document.item("u2") == nil)
    #expect(archive.entries.count == 2)
    #expect(Set(archive.entries.compactMap(\.url)) == [URL(string: "https://u1.example.com/")!, URL(string: "https://u2.example.com/")!])
    #expect(Set(archive.entries.compactMap(\.title)) == ["u1 title", "u2 title"])
    #expect(archive.entries.allSatisfy { $0.spaceID == "S" && $0.archivedAt == now && $0.reason == .inactive })
}

@Test func inactivityCountsFromWhenArchivingStarted() {
    let started = now.addingTimeInterval(-1 * hour)
    #expect(inactiveTabs(in: fixtureDocument(), now: now, after: 12 * hour, protecting: [], notBefore: started).isEmpty)
    #expect(Set(inactiveTabs(in: fixtureDocument(), now: now.addingTimeInterval(12 * hour), after: 12 * hour, protecting: [], notBefore: started)) == ["u1", "u2"])
}

@Test func aSplitArchivesOnlyWhenEveryPaneIsDue() throws {
    var doc = fixtureDocument()
    try doc.addToSplit("u2", with: "u1")
    try doc.updateTab("u2") { $0.lastActiveAt = now.addingTimeInterval(-1 * hour) }
    #expect(inactiveTabs(in: doc, now: now, after: 12 * hour, protecting: []).isEmpty)
    try doc.updateTab("u2") { $0.lastActiveAt = now.addingTimeInterval(-13 * hour) }
    #expect(inactiveTabs(in: doc, now: now, after: 12 * hour, protecting: []) == ["u1", "u2"])
}

@Test func aProtectedPaneProtectsItsSplit() throws {
    var doc = fixtureDocument()
    try doc.addToSplit("u2", with: "u1")
    #expect(inactiveTabs(in: doc, now: now, after: 12 * hour, protecting: ["u2"]).isEmpty)
}

@MainActor @Test func archivingASplitRemovesIt() throws {
    let folder = try temporaryFolder()
    let sidebar = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { now })
    let s = try #require(sidebar.addToSplit("u2", with: "u1"))
    archiveInactiveTabs(sidebar: sidebar, archive: archive, now: now, after: 12 * hour, protecting: [])
    #expect(archive.entries.count == 2)
    #expect(sidebar.document.item(s) == nil)
    #expect(sidebar.document.item("U")?.childIDs == [])
    try sidebar.document.validate()
}

@Test func aSplitInsideAFolderStillArchivesAsAUnit() throws {
    var doc = fixtureDocument()
    try doc.insert(fixtureItem("uf", parent: "U", kind: .folder(FolderInfo(icon: nil, isExpanded: true))), into: "U", at: 0)
    try doc.move("u1", to: "uf", at: nil)
    try doc.move("u2", to: "uf", at: nil)
    try doc.addToSplit("u2", with: "u1")
    try doc.updateTab("u2") { $0.lastActiveAt = now.addingTimeInterval(-1 * hour) }
    #expect(inactiveTabs(in: doc, now: now, after: 12 * hour, protecting: []).isEmpty)
}
