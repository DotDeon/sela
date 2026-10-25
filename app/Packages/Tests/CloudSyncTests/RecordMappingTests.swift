import CloudKit
import Foundation
import SidebarModel
import Testing
@testable import CloudSync

@Test func recordKeysRoundTripThroughRecordNames() {
    for key in [RecordKey.space("S"), .item("p1"), .profile(.default)] {
        #expect(RecordKey(recordName: key.recordName) == key)
    }
    #expect(RecordKey(recordName: "item:") == nil)
    #expect(RecordKey(recordName: "tab:p1") == nil)
    #expect(RecordKey(recordName: "nonsense") == nil)
}

@Test func onlyPinnedSectionsFavouritesSpacesAndProfilesBecomeRecords() {
    let bodies = SidebarRecords.bodies(of: fixtureDocument())
    let itemKeys = Set(bodies.keys.compactMap { key -> ItemID? in
        if case .item(let id) = key { return id }
        return nil
    })
    #expect(itemKeys == ["P", "fold", "p2", "p1", "P2", "q1", "f1", SidebarRecords.favoritesAlias])
    #expect(bodies[.space("S")] != nil && bodies[.space("S2")] != nil)
    #expect(bodies[.profile(.default)] != nil)
    #expect(bodies[.item("U")] == nil && bodies[.item("u1")] == nil)
    #expect(SidebarRecords.itemCount(bodies) == 5)
}

@Test func favouritesTravelUnderOneName() {
    let document = fixtureDocument()
    #expect(itemBody(document, SidebarRecords.favoritesAlias)?.childIDs == ["f1"])
    #expect(itemBody(document, "f1")?.parentID == SidebarRecords.favoritesAlias)
    #expect(itemBody(document, "F") == nil)
}

@Test func whatBelongsToOneMacStaysOutOfTheBody() {
    var document = fixtureDocument()
    try? document.updateTab("p1") { $0.lastActiveAt = fixtureDate }
    try? document.setExpanded("fold", false)
    guard case .tab(let tab)? = itemBody(document, "p1")?.kind, case .folder(let folder)? = itemBody(document, "fold")?.kind else {
        Issue.record("expected a tab and a folder")
        return
    }
    #expect(tab.lastActiveAt == nil)
    #expect(folder.isExpanded)
    #expect(SidebarRecords.bodies(of: document) == SidebarRecords.bodies(of: fixtureDocument()))
}

@Test func spacesAndProfilesKeepTheirOrder() {
    let bodies = SidebarRecords.bodies(of: fixtureDocument())
    guard case .space(let first)? = bodies[.space("S")], case .space(let second)? = bodies[.space("S2")] else {
        Issue.record("expected two spaces")
        return
    }
    #expect(first.order == 0 && second.order == 1)
    #expect(first.pinnedContainerID == "P")
}

@Test func cloudKitRecordsRoundTrip() throws {
    let document = fixtureDocument()
    for key in SidebarRecords.bodies(of: document).keys {
        let outgoing = OutgoingRecord(record: SyncRecord(key: key, tag: tag(5), body: SidebarRecords.bodies(of: document)[key]), systemFields: nil)
        let record = try CloudKitRecords.record(from: outgoing)
        #expect(record.recordID.zoneID == CloudKitRecords.zoneID)
        #expect(record.recordType == CloudKitRecords.recordType(for: key))
        let incoming = try #require(CloudKitRecords.incoming(from: record))
        #expect(incoming.record == outgoing.record)
        #expect(!incoming.systemFields.isEmpty)
    }
}

@Test func tombstonesTravelWithoutABody() throws {
    let record = try CloudKitRecords.record(from: OutgoingRecord(record: tombstone("p1", tag: tag(1)), systemFields: nil))
    #expect(record["deleted"] as? Int64 == 1)
    #expect(record.encryptedValues["body"] == nil)
    let incoming = try #require(CloudKitRecords.incoming(from: record))
    #expect(incoming.record.isTombstone)
    #expect(incoming.record.tag == tag(1))
}

@Test func savedSystemFieldsCarryOverToTheNextSave() throws {
    let first = try CloudKitRecords.record(from: OutgoingRecord(record: record(fixtureDocument(), item: "p1", tag: tag()), systemFields: nil))
    let fields = CloudKitRecords.systemFields(of: first)
    let second = try CloudKitRecords.record(from: OutgoingRecord(record: record(fixtureDocument(), item: "p1", tag: tag(1)), systemFields: fields))
    #expect(second.recordID == first.recordID)
    #expect(second["tagDate"] as? Date == tag(1).date)
}

@Test func recordsThatCantBeReadAreLeftAlone() {
    let wrongType = CKRecord(recordType: "SelaSpace", recordID: CloudKitRecords.recordID(for: .item("p1")))
    wrongType["tagDate"] = Date.now
    wrongType["tagDevice"] = "x"
    #expect(CloudKitRecords.incoming(from: wrongType) == nil)

    let noTag = CKRecord(recordType: "SelaItem", recordID: CloudKitRecords.recordID(for: .item("p1")))
    #expect(CloudKitRecords.incoming(from: noTag) == nil)

    let badBody = CKRecord(recordType: "SelaItem", recordID: CloudKitRecords.recordID(for: .item("p1")))
    badBody["tagDate"] = Date.now
    badBody["tagDevice"] = "x"
    badBody["deleted"] = 0
    badBody.encryptedValues["body"] = Data("{ not json".utf8)
    #expect(CloudKitRecords.incoming(from: badBody) == nil)
}

@Test func onlyTheRightArraysGrantTheEntitlement() {
    #expect(CloudSyncEntitlement.isGranted(services: ["CloudKit"] as CFArray, containers: ["iCloud.app.brow.Brow"] as CFArray))
    #expect(!CloudSyncEntitlement.isGranted(services: ["CloudDocuments"] as CFArray, containers: ["iCloud.app.brow.Brow"] as CFArray))
    #expect(!CloudSyncEntitlement.isGranted(services: ["CloudKit"] as CFArray, containers: ["iCloud.other"] as CFArray))
    #expect(!CloudSyncEntitlement.isGranted(services: "CloudKit" as CFString, containers: ["iCloud.app.brow.Brow"] as CFArray))
    #expect(!CloudSyncEntitlement.isGranted(services: nil, containers: nil))
    #expect(!CloudSyncEntitlement.isPresent)
}
