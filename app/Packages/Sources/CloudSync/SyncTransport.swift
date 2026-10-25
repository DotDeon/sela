import Foundation

/// Whether the Mac is signed in to iCloud, as CloudKit reports it.
public enum AccountStatus: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    public var description: String {
        switch self {
        case .available: "Signed in"
        case .noAccount: "Not signed in"
        case .restricted: "Restricted by parental controls or a profile"
        case .temporarilyUnavailable: "Not available right now"
        case .couldNotDetermine: "Unknown"
        }
    }
}

/// Why syncing stopped, for the Settings tab and the banner.
public enum SyncProblem: Equatable, Sendable {
    case signedOut
    case iCloudFull
    case restricted
    case other(String)

    public var text: String {
        switch self {
        case .signedOut: "Sync is paused because this Mac isn't signed in to iCloud."
        case .iCloudFull: "Sync is paused because your iCloud storage is full."
        case .restricted: "Sync is paused because iCloud is restricted on this Mac."
        case .other(let reason): "Sync couldn't finish. \(reason)"
        }
    }

    /// Problems worth a banner. Others show in Settings only, since the engine tries again by itself.
    public var pausesSync: Bool {
        switch self {
        case .signedOut, .iCloudFull, .restricted: true
        case .other: false
        }
    }
}

public enum AccountChange: Equatable, Sendable {
    case signedIn
    case signedOut
    case switchedAccounts
}

/// What a transport tells the model. The CloudKit one calls these on the main actor from the sync engine's callbacks.
@MainActor
public protocol SyncTransportDelegate: AnyObject {
    /// The records to send for keys the engine is about to save. A key with no record is dropped from the queue.
    func outgoingRecords(for keys: [RecordKey]) -> [OutgoingRecord]
    func transport(_ transport: any SyncTransport, fetched records: [IncomingRecord])
    func transport(_ transport: any SyncTransport, saved key: RecordKey, systemFields: Data)
    /// iCloud holds a version of the record this Mac hasn't seen. The merge decides who wins.
    func transport(_ transport: any SyncTransport, conflict key: RecordKey, server: IncomingRecord)
    /// iCloud no longer has the record, so the next save makes it afresh.
    func transport(_ transport: any SyncTransport, lostServerCopyOf key: RecordKey)
    func transport(_ transport: any SyncTransport, finishedWith problem: SyncProblem?)
    func transport(_ transport: any SyncTransport, accountChanged change: AccountChange)
    func transport(_ transport: any SyncTransport, stateChanged state: Data)
    /// The zone in iCloud was deleted or purged. Everything goes up again.
    func transportZoneWasReset(_ transport: any SyncTransport)
}

/// Moves records between this Mac and iCloud. `CloudKitTransport` does it with `CKSyncEngine`; tests use a stand-in.
@MainActor
public protocol SyncTransport: AnyObject {
    var delegate: (any SyncTransportDelegate)? { get set }
    /// Begins syncing, picking up from `state` when there is one.
    func start(state: Data?)
    func stop()
    func queueSaves(_ keys: [RecordKey])
    /// Fetches and sends now rather than on the engine's schedule.
    func syncNow() async
    func accountStatus() async -> AccountStatus
}
