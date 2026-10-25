import Foundation
import Sidebar
import SidebarModel
import Testing
@testable import CloudSync
@_exported import SelaTestSupport

/// A tag `seconds` after the fixture date, from another Mac unless told otherwise.
func tag(_ seconds: TimeInterval = 0, device: String = "other", name: String = "Other Mac") -> ChangeTag {
    ChangeTag(date: fixtureDate.addingTimeInterval(seconds), deviceID: device, deviceName: name)
}

/// What this Mac would know after syncing the fixture at the fixture date.
func knownTags(_ document: SidebarDocument = fixtureDocument(), tag known: ChangeTag = tag(device: "me", name: "This Mac")) -> [RecordKey: ChangeTag] {
    SidebarRecords.bodies(of: document).mapValues { _ in known }
}

func itemBody(_ document: SidebarDocument, _ id: ItemID) -> SyncRecord.ItemBody? {
    guard case .item(let body)? = SidebarRecords.bodies(of: document)[.item(id)] else { return nil }
    return body
}

func record(_ document: SidebarDocument, item id: ItemID, tag: ChangeTag, change: (inout SyncRecord.ItemBody) -> Void = { _ in }) -> SyncRecord {
    var body = itemBody(document, id)!
    change(&body)
    return SyncRecord(key: .item(id), tag: tag, body: .item(body))
}

func tombstone(_ id: ItemID, tag: ChangeTag) -> SyncRecord {
    SyncRecord(key: .item(id), tag: tag, body: nil)
}

func merge(_ incoming: [SyncRecord], into document: SidebarDocument = fixtureDocument(), known: [RecordKey: ChangeTag]? = nil) -> SyncMerge.Result {
    SyncMerge.merge(incoming, into: document, known: known ?? knownTags(document), localDeviceName: "This Mac", now: fixtureDate)
}

/// The "Recovered from" folder in the first space's pinned section, if there is one.
func recoveredFolder(in document: SidebarDocument, from device: String = "Other Mac") -> SidebarItem? {
    document.children(of: document.spaces[0].pinnedContainerID).first { $0.title == "Recovered from \(device)" }
}

/// A transport that remembers what it was asked and lets a test play iCloud.
@MainActor
final class FakeTransport: SyncTransport {
    weak var delegate: (any SyncTransportDelegate)?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var startState: Data?
    private(set) var queued: [RecordKey] = []
    private(set) var syncs = 0
    var status: AccountStatus = .available

    func start(state: Data?) {
        starts += 1
        startState = state
    }

    func stop() { stops += 1 }

    func queueSaves(_ keys: [RecordKey]) { queued += keys }

    func syncNow() async {
        syncs += 1
        delegate?.transport(self, finishedWith: nil)
    }

    func accountStatus() async -> AccountStatus { status }

    func clearQueue() { queued = [] }

    /// What would go up for everything queued, by key.
    func outgoing() -> [RecordKey: OutgoingRecord] {
        Dictionary((delegate?.outgoingRecords(for: queued) ?? []).map { ($0.record.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    func deliver(_ records: [SyncRecord]) {
        delegate?.transport(self, fetched: records.map { IncomingRecord(record: $0, systemFields: Data([1])) })
    }
}

@MainActor
func makeModel(
    folder: URL? = nil,
    transport: FakeTransport = FakeTransport(),
    defaults: UserDefaults? = nil,
    document: @escaping () -> SidebarDocument = fixtureDocument
) throws -> (CloudSyncModel, SidebarStore, FakeTransport, UserDefaults) {
    let folder = try folder ?? temporaryFolder()
    let defaults = defaults ?? UserDefaults(suiteName: "CloudSyncTests-\(UUID().uuidString)")!
    let sidebar = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .milliseconds(20),
                               now: { fixtureDate }, firstRunDocument: document)
    let model = CloudSyncModel(sidebar: sidebar, transport: transport, ledgerStore: SyncLedgerStore(fileURL: folder.appending(path: "CloudSync.json")),
                               defaults: defaults, deviceName: "This Mac", compareDelay: .milliseconds(20), now: { fixtureDate })
    return (model, sidebar, transport, defaults)
}

/// Polls every 10 ms for up to 2 seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
