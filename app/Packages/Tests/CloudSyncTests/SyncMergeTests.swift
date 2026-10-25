import Foundation
import SidebarModel
import Testing
@testable import CloudSync

@Test func nothingIncomingChangesNothing() {
    let result = merge([])
    #expect(result.document == fixtureDocument())
    #expect(result.applied.isEmpty && result.removedItems == 0 && result.recoveredItems == 0)
    #expect(!result.removesMostItems)
}

@Test func theLaterTagWins() {
    let newer = merge([record(fixtureDocument(), item: "p1", tag: tag(10)) { $0.title = "Mail" }])
    #expect(newer.document.item("p1")?.title == "Mail")
    #expect(newer.applied.keys.contains(.item("p1")))

    let older = merge([record(fixtureDocument(), item: "p1", tag: tag(-10)) { $0.title = "Mail" }])
    #expect(older.document.item("p1")?.title == nil)
    #expect(older.ignored == [.item("p1")])
}

@Test func theSameTagFromAnotherMacIsNotNewer() {
    let result = merge([record(fixtureDocument(), item: "p1", tag: tag(device: "me", name: "This Mac")) { $0.title = "Mail" }])
    #expect(result.document.item("p1")?.title == nil)
}

@Test func aNewerTombstoneRemovesTheItem() {
    let result = merge([tombstone("p1", tag: tag(1))])
    #expect(result.document.item("p1") == nil)
    #expect(result.document.item("P")?.childIDs == ["fold"])
    #expect(result.removedItems == 1 && result.localItems == 5)
    #expect(!result.removesMostItems)
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func anOlderTombstoneLosesToALocalEdit() {
    let result = merge([tombstone("p1", tag: tag(-1))])
    #expect(result.document.item("p1") != nil)
    #expect(result.ignored == [.item("p1")])
}

@Test func removingMostItemsIsFlagged() {
    let result = merge([tombstone("fold", tag: tag(1)), tombstone("p2", tag: tag(1)), tombstone("p1", tag: tag(1))])
    #expect(result.removedItems == 3)
    #expect(result.removesMostItems)
}

@Test func removingSpacesDoesNotLeaveTheirLocalTabsBehind() {
    var document = fixtureDocument()
    try! document.insert(fixtureTab("today", parent: "U2"), into: "U2", at: nil)
    let result = merge([
        SyncRecord(key: .space("S2"), tag: tag(1), body: nil), tombstone("P2", tag: tag(1)), tombstone("q1", tag: tag(1)),
    ], into: document)
    #expect(result.document.spaces.map(\.id) == ["S"])
    #expect(result.document.item("q1") == nil)
    #expect(result.document.item("today") != nil)
    #expect(recoveredFolder(in: result.document, from: "This Mac")?.childIDs == ["today"])
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func deletingEverySpaceKeepsThisMacs() {
    let result = merge([SyncRecord(key: .space("S"), tag: tag(1), body: nil), SyncRecord(key: .space("S2"), tag: tag(1), body: nil)])
    #expect(result.document.spaces.map(\.id) == ["S", "S2"])
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func anItemWithoutAHomeGoesToARecoveredFolder() {
    let orphan = SyncRecord(key: .item("new"), tag: tag(1, name: "Studio"), body: .item(.init(
        parentID: "missing", childIDs: [], title: nil, createdAt: fixtureDate,
        kind: .tab(TabInfo(savedURL: URL(string: "https://new.example.com/"), savedTitle: "New", lastActiveAt: nil, isMuted: false)))))
    let result = merge([orphan])
    let folder = recoveredFolder(in: result.document, from: "Studio")
    #expect(folder?.childIDs == ["new"])
    #expect(folder?.parentID == "P")
    #expect(result.document.item("new")?.parentID == folder?.id)
    #expect(result.recoveredItems == 1)
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func recoveredItemsFromTheSameMacShareAFolder() {
    func orphan(_ id: ItemID) -> SyncRecord {
        SyncRecord(key: .item(id), tag: tag(1), body: .item(.init(parentID: "missing", childIDs: [], title: nil, createdAt: fixtureDate,
                                                                  kind: .tab(TabInfo(savedURL: nil, savedTitle: nil, lastActiveAt: nil, isMuted: false)))))
    }
    let result = merge([orphan("a"), orphan("b")])
    #expect(recoveredFolder(in: result.document)?.childIDs == ["a", "b"])
    #expect(result.document.children(of: "P").filter { $0.title?.hasPrefix("Recovered") == true }.count == 1)
}

@Test func aSpaceThatNamesANewPinnedSectionKeepsTheOldOnesItems() {
    let document = fixtureDocument()
    var space = SidebarRecords.bodies(of: document)[.space("S")]!
    if case .space(var body) = space {
        body.pinnedContainerID = "PX"
        space = .space(body)
    }
    let container = SyncRecord(key: .item("PX"), tag: tag(1), body: .item(.init(parentID: nil, childIDs: ["x1"], title: nil, createdAt: fixtureDate, kind: .container(.pinned("S")))))
    let tab = SyncRecord(key: .item("x1"), tag: tag(1), body: .item(.init(parentID: "PX", childIDs: [], title: nil, createdAt: fixtureDate,
                                                                            kind: .tab(TabInfo(savedURL: nil, savedTitle: "X", lastActiveAt: nil, isMuted: false)))))
    let result = merge([SyncRecord(key: .space("S"), tag: tag(1), body: space), container, tab])
    #expect(result.document.space("S")?.pinnedContainerID == "PX")
    #expect(result.document.item("P") == nil)
    // The old section was this Mac's, so its items are recovered under this Mac's name.
    let folder = recoveredFolder(in: result.document, from: "This Mac")
    #expect(folder?.parentID == "PX")
    #expect(Set(folder?.childIDs ?? []) == ["fold", "p1"])
    #expect(result.document.item("p2")?.parentID == "fold")
    #expect(result.removedItems == 0)
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func aSpaceFromAnotherMacGetsItsOwnUnpinnedSectionHere() {
    let space = SyncRecord(key: .space("S3"), tag: tag(1), body: .space(.init(title: "Three", icon: nil, theme: nil, pinnedContainerID: "P3", profileID: .default, order: 2)))
    let container = SyncRecord(key: .item("P3"), tag: tag(1), body: .item(.init(parentID: nil, childIDs: ["r1"], title: nil, createdAt: fixtureDate, kind: .container(.pinned("S3")))))
    let tab = SyncRecord(key: .item("r1"), tag: tag(1), body: .item(.init(parentID: "P3", childIDs: [], title: nil, createdAt: fixtureDate,
                                                                            kind: .tab(TabInfo(savedURL: nil, savedTitle: "R", lastActiveAt: nil, isMuted: false)))))
    let result = merge([space, container, tab])
    let added = result.document.space("S3")
    #expect(result.document.spaces.map(\.id) == ["S", "S2", "S3"])
    #expect(added?.pinnedContainerID == "P3")
    #expect(result.document.item(added!.unpinnedContainerID)?.kind == .container(.unpinned("S3")))
    #expect(result.document.item("r1")?.parentID == "P3")
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func aPinnedSectionThatArrivesBeforeItsSpaceStillWorks() {
    let space = SyncRecord(key: .space("S3"), tag: tag(1), body: .space(.init(title: "Three", icon: nil, theme: nil, pinnedContainerID: "P3", profileID: .default, order: 2)))
    let result = merge([space])
    #expect(result.document.item("P3")?.kind == .container(.pinned("S3")))
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func aChildsOwnRecordSaysWhereItLives() {
    // Another Mac moved p2 out of the folder to the top of the section, but only p2's record has arrived so far.
    let result = merge([record(fixtureDocument(), item: "p2", tag: tag(1)) { $0.parentID = "P" }])
    #expect(result.document.item("p2")?.parentID == "P")
    #expect(result.document.item("fold")?.childIDs == [])
    #expect(result.document.item("P")?.childIDs == ["fold", "p1", "p2"])
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func foldersInsideEachOtherComeApart() {
    var document = fixtureDocument()
    let inner = ItemID("inner")
    try! document.insert(fixtureItem(inner, parent: "P", kind: .folder(FolderInfo(icon: nil, isExpanded: true))), into: "P", at: nil)
    let result = merge([
        record(document, item: "fold", tag: tag(1)) { $0.parentID = inner },
        record(document, item: inner, tag: tag(1)) { $0.parentID = "fold" },
    ], into: document)
    #expect(result.document.item("fold") != nil && result.document.item(inner) != nil)
    #expect(result.document.item("p2") != nil)
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func aSplitLeftWithOnePaneGivesWayToIt() {
    var document = fixtureDocument()
    try! document.addToSplit("p1", with: "p2")
    let splitID = document.splitID(containing: "p1")!
    let result = merge([tombstone("p1", tag: tag(1))], into: document)
    #expect(result.document.item(splitID) == nil)
    #expect(result.document.item("p2")?.parentID == "fold")
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func thisMacsOwnStateSurvivesAMerge() {
    var document = fixtureDocument()
    try! document.updateTab("p1") { $0.lastActiveAt = fixtureDate }
    try! document.setExpanded("fold", false)
    let result = merge([record(document, item: "p1", tag: tag(1)) { $0.title = "Mail" }, record(document, item: "fold", tag: tag(1)) { $0.title = "Work" }], into: document)
    #expect(tabInfo(result.document, "p1")?.lastActiveAt == fixtureDate)
    #expect(result.document.item("fold")?.kind == .folder(FolderInfo(icon: nil, isExpanded: false)))
    #expect(result.document.item("fold")?.title == "Work")
    for space in result.document.spaces {
        #expect(result.document.item(space.unpinnedContainerID)?.childIDs == document.item(space.unpinnedContainerID)?.childIDs)
    }
}

@Test func aTabPinnedElsewhereLeavesTodaysTabsHere() {
    let pinned = SyncRecord(key: .item("u1"), tag: tag(1), body: .item(.init(parentID: "P", childIDs: [], title: nil, createdAt: fixtureDate,
                                                                              kind: .tab(TabInfo(savedURL: nil, savedTitle: "U1", lastActiveAt: nil, isMuted: false)))))
    let result = merge([pinned])
    #expect(result.document.item("u1")?.parentID == "P")
    #expect(result.document.item("U")?.childIDs == ["u2"])
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func profilesAndSpaceOrderFollowTheRecords() {
    let profile = SyncRecord(key: .profile("work"), tag: tag(1), body: .profile(.init(name: "Work", icon: nil, color: nil, order: 1)))
    var space = SidebarRecords.bodies(of: fixtureDocument())[.space("S2")]!
    if case .space(var body) = space {
        body.order = -1
        body.profileID = "work"
        body.title = "Second"
        space = .space(body)
    }
    let result = merge([profile, SyncRecord(key: .space("S2"), tag: tag(1), body: space)])
    #expect(result.document.spaces.map(\.id) == ["S2", "S"])
    #expect(result.document.space("S2")?.profileID == "work")
    #expect(result.document.space("S2")?.title == "Second")
    #expect(result.document.profiles.map(\.id) == [.default, "work"])
    #expect(throws: Never.self) { try result.document.validate() }
}

@Test func ledgerNoticesLocalChangesAndDeletions() {
    var ledger = SyncLedger(deviceID: "me")
    let first = ledger.noteLocal(SidebarRecords.bodies(of: fixtureDocument()), tag: tag())
    #expect(first.count == 11)
    #expect(ledger.pending.count == 11)

    var document = fixtureDocument()
    try! document.setTitle("p1", "Mail")
    try! document.remove("q1")
    ledger.pending = []
    let changed = ledger.noteLocal(SidebarRecords.bodies(of: document), tag: tag(1))
    #expect(Set(changed) == [.item("p1"), .item("q1"), .item("P2")])
    #expect(ledger.known[.item("q1")]?.body == nil)
    #expect(ledger.known[.item("q1")]?.tag == tag(1))
    #expect(ledger.outgoing(.item("q1"))?.record.isTombstone == true)
    #expect(ledger.noteLocal(SidebarRecords.bodies(of: document), tag: tag(2)).isEmpty)
}

@Test func ledgerRoundTripsThroughItsFile() throws {
    var ledger = SyncLedger(deviceID: "me")
    ledger.noteLocal(SidebarRecords.bodies(of: fixtureDocument()), tag: tag())
    ledger.noteSaved(.item("p1"), systemFields: Data([1, 2]))
    ledger.engineState = Data([3])
    ledger.lastSyncAt = fixtureDate
    let store = SyncLedgerStore(fileURL: try temporaryFolder().appending(path: "CloudSync.json"))
    try store.save(ledger)
    #expect(store.load() == ledger)
    #expect(SyncLedgerStore(fileURL: URL(fileURLWithPath: "/nonexistent/CloudSync.json")).load().known.isEmpty)
}
