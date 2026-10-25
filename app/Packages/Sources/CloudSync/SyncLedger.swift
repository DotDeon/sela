import Foundation
import SidebarModel

/// What this Mac knows about every record: the tag and body it last saw, locally or from iCloud, and the
/// CloudKit bookkeeping for it. Saved beside Sidebar.json as CloudSync.json. Sidebar.json stays the sidebar;
/// losing this file only means a full compare on the next sync.
public struct SyncLedger: Codable, Equatable, Sendable {
    public struct Known: Codable, Equatable, Sendable {
        public var tag: ChangeTag
        /// Nil for a record this Mac deleted: a tombstone.
        public var body: SyncRecord.Body?
        /// CloudKit's own fields for the record, so a save says which version it changes. Nil until it's been saved or fetched.
        public var systemFields: Data?

        public init(tag: ChangeTag, body: SyncRecord.Body?, systemFields: Data? = nil) {
            self.tag = tag
            self.body = body
            self.systemFields = systemFields
        }
    }

    /// Made once per data folder, so tags from two Macs never tie.
    public var deviceID: String
    public var known: [RecordKey: Known]
    /// Records changed here and not yet saved to iCloud.
    public var pending: Set<RecordKey>
    /// The sync engine's own saved state, which it uses to pick up where it left off.
    public var engineState: Data?
    public var lastSyncAt: Date?

    public init(deviceID: String = UUID().uuidString) {
        self.deviceID = deviceID
        known = [:]
        pending = []
    }

    public var tags: [RecordKey: ChangeTag] {
        known.mapValues(\.tag)
    }

    /// Compares the sidebar with what's known. New and changed records get `tag`, and records that have gone become
    /// tombstones. Returns the keys that changed, which are now pending.
    @discardableResult
    public mutating func noteLocal(_ bodies: [RecordKey: SyncRecord.Body], tag: ChangeTag) -> [RecordKey] {
        var changed: [RecordKey] = []
        for (key, body) in bodies where known[key]?.body != body {
            known[key] = Known(tag: tag, body: body, systemFields: known[key]?.systemFields)
            changed.append(key)
        }
        for (key, entry) in known where entry.body != nil && bodies[key] == nil {
            known[key] = Known(tag: tag, body: nil, systemFields: entry.systemFields)
            changed.append(key)
        }
        pending.formUnion(changed)
        return changed.sorted { $0.recordName < $1.recordName }
    }

    /// Records from iCloud that won the merge. They're the truth now, so they're no longer pending.
    public mutating func noteApplied(_ records: [RecordKey: SyncRecord], systemFields: [RecordKey: Data] = [:]) {
        for (key, record) in records {
            known[key] = Known(tag: record.tag, body: record.body, systemFields: systemFields[key] ?? known[key]?.systemFields)
            pending.remove(key)
        }
    }

    public mutating func noteSaved(_ key: RecordKey, systemFields: Data) {
        known[key]?.systemFields = systemFields
        pending.remove(key)
    }

    /// Gives records a fresh tag so they win over what iCloud holds, such as items the person chose to keep.
    public mutating func markChanged(_ keys: some Sequence<RecordKey>, tag: ChangeTag) {
        for key in keys where known[key] != nil {
            known[key]!.tag = tag
            pending.insert(key)
        }
    }

    /// The record to send for a key, or nil when there's nothing known about it.
    public func outgoing(_ key: RecordKey) -> OutgoingRecord? {
        guard let entry = known[key] else { return nil }
        return OutgoingRecord(record: SyncRecord(key: key, tag: entry.tag, body: entry.body), systemFields: entry.systemFields)
    }

    /// After iCloud's copy went away, through a sign-out or a reset: everything known goes up again as new records.
    public mutating func forgetServer() {
        for key in known.keys { known[key]!.systemFields = nil }
        pending = Set(known.keys)
        engineState = nil
    }
}

/// A record on its way to iCloud.
public struct OutgoingRecord: Equatable, Sendable {
    public var record: SyncRecord
    public var systemFields: Data?

    public init(record: SyncRecord, systemFields: Data?) {
        self.record = record
        self.systemFields = systemFields
    }
}

/// A record that arrived from iCloud.
public struct IncomingRecord: Equatable, Sendable {
    public var record: SyncRecord
    public var systemFields: Data

    public init(record: SyncRecord, systemFields: Data) {
        self.record = record
        self.systemFields = systemFields
    }
}

/// Reads and writes the ledger file. An unreadable file starts a fresh ledger.
public struct SyncLedgerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> SyncLedger {
        guard let data = try? Data(contentsOf: fileURL), let ledger = try? Self.decoder.decode(SyncLedger.self, from: data) else {
            return SyncLedger()
        }
        return ledger
    }

    public func save(_ ledger: SyncLedger) throws {
        try Self.encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
