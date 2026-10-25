import CloudKit
import Foundation

/// How a `SyncRecord` looks as a `CKRecord`. The body travels as one encrypted JSON field, so CloudKit's schema
/// is three record types with the same handful of fields and the sidebar's shape can change without touching it.
public enum CloudKitRecords {
    /// One zone of the private database holds the sidebar, so the engine can fetch its changes in one go.
    public static let zoneID = CKRecordZone.ID(zoneName: "SelaSidebar", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let tagDate = "tagDate"
        static let tagDevice = "tagDevice"
        static let tagDeviceName = "tagDeviceName"
        static let deleted = "deleted"
        static let body = "body"
    }

    public static func recordID(for key: RecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.recordName, zoneID: zoneID)
    }

    public static func recordType(for key: RecordKey) -> CKRecord.RecordType {
        switch key {
        case .space: "SelaSpace"
        case .item: "SelaItem"
        case .profile: "SelaProfile"
        }
    }

    /// The record to save. Starts from the saved system fields when there are any, so CloudKit knows which
    /// version this one replaces and can report a conflict otherwise.
    public static func record(from outgoing: OutgoingRecord) throws -> CKRecord {
        let key = outgoing.record.key
        let record = try outgoing.systemFields.flatMap { try record(fromSystemFields: $0) }
            ?? CKRecord(recordType: recordType(for: key), recordID: recordID(for: key))
        record[Field.tagDate] = outgoing.record.tag.date
        record[Field.tagDevice] = outgoing.record.tag.deviceID
        record[Field.tagDeviceName] = outgoing.record.tag.deviceName
        record[Field.deleted] = outgoing.record.isTombstone ? 1 : 0
        record.encryptedValues[Field.body] = try outgoing.record.body.map { try encoder.encode($0) }
        return record
    }

    /// Nil for a record that isn't one of ours or doesn't decode, which the merge then leaves alone.
    public static func incoming(from record: CKRecord) -> IncomingRecord? {
        guard let key = RecordKey(recordName: record.recordID.recordName), recordType(for: key) == record.recordType,
              let date = record[Field.tagDate] as? Date, let deviceID = record[Field.tagDevice] as? String
        else { return nil }
        let tag = ChangeTag(date: date, deviceID: deviceID, deviceName: record[Field.tagDeviceName] as? String ?? "")
        let deleted = (record[Field.deleted] as? Int64 ?? 0) != 0
        var body: SyncRecord.Body?
        if !deleted {
            guard let data = record.encryptedValues[Field.body] as? Data, let decoded = try? decoder.decode(SyncRecord.Body.self, from: data) else { return nil }
            body = decoded
        }
        return IncomingRecord(record: SyncRecord(key: key, tag: tag, body: body), systemFields: systemFields(of: record))
    }

    public static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    static func record(fromSystemFields data: Data) throws -> CKRecord? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
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
