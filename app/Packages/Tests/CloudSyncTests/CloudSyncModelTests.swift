import Foundation
import SidebarModel
import Testing
@testable import CloudSync

@MainActor @Test func syncIsOffUntilTurnedOn() throws {
    let (model, _, transport, defaults) = try makeModel()
    #expect(!model.isEnabled)
    #expect(transport.starts == 0 && transport.queued.isEmpty)
    model.setEnabled(true)
    #expect(model.isEnabled)
    #expect(defaults.bool(forKey: CloudSyncModel.enabledKey))
    #expect(transport.starts == 1)
    model.setEnabled(false)
    #expect(transport.stops == 1)
    #expect(!defaults.bool(forKey: CloudSyncModel.enabledKey))
}

@MainActor @Test func turningOnSendsEverythingWithVeryOldTags() throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    let bodies = SidebarRecords.bodies(of: sidebar.document)
    #expect(Set(transport.queued) == Set(bodies.keys))
    let outgoing = transport.outgoing()
    #expect(outgoing.count == bodies.count)
    #expect(outgoing.values.allSatisfy { $0.record.tag.date == .distantPast && $0.record.tag.deviceName == "This Mac" })
    #expect(outgoing[.item("p1")]?.record.body == bodies[.item("p1")])
}

@MainActor @Test func anEditSendsOnlyWhatChanged() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.clearQueue()
    sidebar.rename("p1", to: "Mail")
    try await eventually { !transport.queued.isEmpty }
    #expect(transport.queued == [.item("p1")])
    #expect(transport.outgoing()[.item("p1")]?.record.tag.date == fixtureDate)
    _ = model
}

@MainActor @Test func todaysTabsDontSync() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.clearQueue()
    sidebar.createTab(url: URL(string: "https://today.example.com/"), title: "Today", in: "U", at: 0)
    try await Task.sleep(for: .milliseconds(100))
    #expect(transport.queued.isEmpty)
    _ = model
}

@MainActor @Test func nothingIsWatchedWhileSyncIsOff() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    for key in transport.queued { model.transport(transport, saved: key, systemFields: Data([1])) }
    model.setEnabled(false)
    transport.clearQueue()
    sidebar.rename("p1", to: "Mail")
    try await Task.sleep(for: .milliseconds(100))
    #expect(transport.queued.isEmpty)
    model.setEnabled(true)
    #expect(transport.queued == [.item("p1")])
}

@MainActor @Test func aRecordFromICloudChangesTheSidebarWithoutAnEcho() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.clearQueue()
    transport.deliver([record(sidebar.document, item: "p1", tag: tag(10)) { $0.title = "Mail" }])
    #expect(sidebar.document.item("p1")?.title == "Mail")
    try await Task.sleep(for: .milliseconds(100))
    #expect(transport.queued.isEmpty)
    #expect(model.ledger.known[.item("p1")]?.tag == tag(10))
    #expect(model.ledger.known[.item("p1")]?.systemFields == Data([1]))
}

@MainActor @Test func aRepairedSidebarSendsTheRepair() throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.clearQueue()
    let orphan = SyncRecord(key: .item("new"), tag: tag(1), body: .item(.init(parentID: "missing", childIDs: [], title: nil, createdAt: fixtureDate,
                                                                              kind: .tab(TabInfo(savedURL: nil, savedTitle: "New", lastActiveAt: nil, isMuted: false)))))
    transport.deliver([orphan])
    let folder = try #require(recoveredFolder(in: sidebar.document))
    #expect(Set(transport.queued) == [.item(folder.id), .item("new"), .item("P")])
}

@MainActor @Test func removingMostItemsWaitsAndKeepingThemSendsThemBack() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.clearQueue()
    let tombstones = [tombstone("fold", tag: tag(1)), tombstone("p2", tag: tag(1)), tombstone("p1", tag: tag(1))]
    transport.deliver(tombstones)
    #expect(model.pendingRemoval?.removedItems == 3)
    #expect(model.pendingRemoval?.localItems == 5)
    #expect(sidebar.document.item("p1") != nil)
    #expect(transport.queued.isEmpty)

    // More arrives while the question is open and waits with the rest.
    transport.deliver([record(sidebar.document, item: "q1", tag: tag(2)) { $0.title = "Q" }])
    #expect(sidebar.document.item("q1")?.title == nil)

    model.resolvePendingRemoval(applying: false)
    #expect(model.pendingRemoval == nil)
    #expect(sidebar.document.item("p1") != nil && sidebar.document.item("fold") != nil)
    #expect(sidebar.document.item("q1")?.title == "Q")
    #expect(Set(transport.queued) == [.item("fold"), .item("p2"), .item("p1")])
    let sent = transport.outgoing()
    #expect(sent[.item("p1")]?.record.tag.date == fixtureDate)
    #expect(sent[.item("p1")]?.record.isTombstone == false)
}

@MainActor @Test func removingMostItemsCanBeAccepted() throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    transport.deliver([tombstone("fold", tag: tag(1)), tombstone("p2", tag: tag(1)), tombstone("p1", tag: tag(1))])
    model.resolvePendingRemoval(applying: true)
    #expect(sidebar.document.item("p1") == nil && sidebar.document.item("fold") == nil && sidebar.document.item("p2") == nil)
    #expect(throws: Never.self) { try sidebar.document.validate() }
}

@MainActor @Test func aConflictThisMacWinsIsSentAgain() async throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    sidebar.rename("p1", to: "Mail")
    model.compareNow()
    transport.clearQueue()
    let server = IncomingRecord(record: record(fixtureDocument(), item: "p1", tag: tag(-5)) { $0.title = "Theirs" }, systemFields: Data([9]))
    model.transport(transport, conflict: .item("p1"), server: server)
    #expect(sidebar.document.item("p1")?.title == "Mail")
    #expect(transport.queued == [.item("p1")])
    #expect(transport.outgoing()[.item("p1")]?.systemFields == Data([9]))
}

@MainActor @Test func aConflictTheOtherMacWinsIsTaken() throws {
    let (model, sidebar, transport, _) = try makeModel()
    model.setEnabled(true)
    sidebar.rename("p1", to: "Mail")
    model.compareNow()
    transport.clearQueue()
    let server = IncomingRecord(record: record(fixtureDocument(), item: "p1", tag: tag(5)) { $0.title = "Theirs" }, systemFields: Data([9]))
    model.transport(transport, conflict: .item("p1"), server: server)
    #expect(sidebar.document.item("p1")?.title == "Theirs")
    #expect(transport.queued.isEmpty)
}

@MainActor @Test func finishingASyncRecordsTheTime() async throws {
    let (model, _, transport, _) = try makeModel()
    model.setEnabled(true)
    #expect(model.lastSyncAt == nil)
    await model.syncNow()
    #expect(transport.syncs == 1)
    #expect(model.lastSyncAt == fixtureDate)
    #expect(model.accountStatus == .available)
}

@MainActor @Test func aSignedOutMacPausesSync() async throws {
    let transport = FakeTransport()
    transport.status = .noAccount
    let (model, _, _, _) = try makeModel(transport: transport)
    model.setEnabled(true)
    await model.refreshAccountStatus()
    #expect(model.problem == .signedOut)
    #expect(model.problem?.pausesSync == true)
    await model.syncNow()
    #expect(transport.syncs == 0)
    transport.status = .available
    await model.refreshAccountStatus()
    #expect(model.problem == nil)
}

@MainActor @Test func aFullICloudPausesSyncUntilItSucceeds() throws {
    let (model, _, transport, _) = try makeModel()
    model.setEnabled(true)
    model.transport(transport, finishedWith: .iCloudFull)
    #expect(model.problem == .iCloudFull)
    model.transport(transport, finishedWith: nil)
    #expect(model.problem == .iCloudFull)
    model.transport(transport, finishedWith: .other("Network"))
    model.transport(transport, finishedWith: nil)
    #expect(model.problem == nil)
}

@MainActor @Test func signingOutAndBackInStartsOver() throws {
    let (model, _, transport, _) = try makeModel()
    model.setEnabled(true)
    model.transport(transport, saved: .item("p1"), systemFields: Data([1]))
    model.transport(transport, accountChanged: .signedOut)
    #expect(model.problem == .signedOut)
    #expect(model.ledger.known[.item("p1")]?.systemFields == nil)
    transport.clearQueue()
    model.transport(transport, accountChanged: .signedIn)
    #expect(model.problem == nil)
    #expect(transport.starts == 2)
    #expect(Set(transport.queued) == Set(model.ledger.known.keys))
}

@MainActor @Test func theLedgerSurvivesARelaunch() async throws {
    let folder = try temporaryFolder()
    let defaults = UserDefaults(suiteName: "CloudSyncTests-\(UUID().uuidString)")!
    let (first, sidebar, transport, _) = try makeModel(folder: folder, defaults: defaults)
    first.setEnabled(true)
    for key in transport.queued { first.transport(transport, saved: key, systemFields: Data([1])) }
    first.transport(transport, stateChanged: Data([7]))
    sidebar.rename("p1", to: "Mail")
    first.compareNow()
    sidebar.saveNow()

    let again = FakeTransport()
    let (second, _, _, _) = try makeModel(folder: folder, transport: again, defaults: defaults)
    #expect(second.isEnabled)
    #expect(again.starts == 1)
    #expect(again.startState == Data([7]))
    #expect(again.queued == [.item("p1")])
    #expect(second.ledger.deviceID == first.ledger.deviceID)
}
