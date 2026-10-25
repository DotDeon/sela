import CloudKit
import Foundation
import OSLog

/// Syncs through `CKSyncEngine`, which batches, retries, listens for pushes and follows account changes.
/// Only make one in a copy of Sela with `CloudSyncEntitlement.isPresent`; without it CloudKit refuses everything.
@MainActor
public final class CloudKitTransport: SyncTransport {
    public weak var delegate: (any SyncTransportDelegate)?

    private let container: CKContainer
    private var engine: CKSyncEngine?
    private let proxy = Proxy()
    private let log = Logger(subsystem: "app.sela", category: "CloudSync")

    public init(containerIdentifier: String = CloudSyncEntitlement.containerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        proxy.transport = self
    }

    public func start(state: Data?) {
        guard engine == nil else { return }
        let serialization = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: serialization, delegate: proxy)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        // Saving the zone again is harmless, and it comes back after a reset without more bookkeeping.
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitRecords.zoneID))])
        self.engine = engine
    }

    public func stop() {
        guard let engine else { return }
        self.engine = nil
        Task { await engine.cancelOperations() }
    }

    public func queueSaves(_ keys: [RecordKey]) {
        engine?.state.add(pendingRecordZoneChanges: keys.map { .saveRecord(CloudKitRecords.recordID(for: $0)) })
    }

    public func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            delegate?.transport(self, finishedWith: Self.problem(for: error))
        }
    }

    public func accountStatus() async -> AccountStatus {
        switch try? await container.accountStatus() {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine, nil: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }

    // MARK: Engine callbacks

    fileprivate func outgoingRecords(for pending: [CKSyncEngine.PendingRecordZoneChange]) -> [CKRecord.ID: CKRecord] {
        let keys = pending.compactMap { change -> RecordKey? in
            guard case .saveRecord(let id) = change else { return nil }
            return RecordKey(recordName: id.recordName)
        }
        var records: [CKRecord.ID: CKRecord] = [:]
        for outgoing in delegate?.outgoingRecords(for: keys) ?? [] {
            do {
                let record = try CloudKitRecords.record(from: outgoing)
                records[record.recordID] = record
            } catch {
                log.error("Couldn't make a record for \(outgoing.record.key): \(error.localizedDescription)")
            }
        }
        return records
    }

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                delegate?.transport(self, stateChanged: data)
            }
        case .accountChange(let change):
            switch change.changeType {
            case .signIn: delegate?.transport(self, accountChanged: .signedIn)
            case .signOut: delegate?.transport(self, accountChanged: .signedOut)
            case .switchAccounts: delegate?.transport(self, accountChanged: .switchedAccounts)
            @unknown default: break
            }
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == CloudKitRecords.zoneID }) {
                delegate?.transportZoneWasReset(self)
            }
        case .fetchedRecordZoneChanges(let changes):
            // Records only ever go away as tombstones, so a hard deletion means someone cleared the data by
            // hand. The zone deletion that comes with that is handled above, so there's nothing to do here.
            let records = changes.modifications.compactMap { CloudKitRecords.incoming(from: $0.record) }
            if records.count < changes.modifications.count {
                log.notice("Ignored \(changes.modifications.count - records.count) records that couldn't be read")
            }
            if !records.isEmpty { delegate?.transport(self, fetched: records) }
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                guard let key = RecordKey(recordName: record.recordID.recordName) else { continue }
                delegate?.transport(self, saved: key, systemFields: CloudKitRecords.systemFields(of: record))
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(of: failure.record, error: failure.error)
            }
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                log.error("Couldn't save the zone: \(failure.error.localizedDescription)")
                delegate?.transport(self, finishedWith: Self.problem(for: failure.error))
            }
        case .didFetchRecordZoneChanges(let fetched):
            if let error = fetched.error { delegate?.transport(self, finishedWith: Self.problem(for: error)) }
        case .didFetchChanges, .didSendChanges:
            delegate?.transport(self, finishedWith: nil)
        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            break
        @unknown default:
            break
        }
    }

    private func handleFailedSave(of record: CKRecord, error: CKError) {
        guard let key = RecordKey(recordName: record.recordID.recordName) else { return }
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord, let incoming = CloudKitRecords.incoming(from: server) else {
                delegate?.transport(self, lostServerCopyOf: key)
                return
            }
            delegate?.transport(self, conflict: key, server: incoming)
        case .unknownItem:
            delegate?.transport(self, lostServerCopyOf: key)
        case .zoneNotFound, .userDeletedZone:
            delegate?.transportZoneWasReset(self)
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated, .accountTemporarilyUnavailable:
            // The engine tries these again itself.
            delegate?.transport(self, finishedWith: Self.problem(for: error))
        default:
            log.error("Couldn't save \(key): \(error.localizedDescription)")
            delegate?.transport(self, finishedWith: Self.problem(for: error))
        }
    }

    static func problem(for error: any Error) -> SyncProblem {
        switch (error as? CKError)?.code {
        case .quotaExceeded: .iCloudFull
        case .notAuthenticated: .signedOut
        case .managedAccountRestricted: .restricted
        default: .other(error.localizedDescription)
        }
    }

    /// The engine's delegate. It's called off the main actor, so it hops over to the transport.
    private final class Proxy: CKSyncEngineDelegate, @unchecked Sendable {
        weak var transport: CloudKitTransport?

        func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
            await MainActor.run { transport?.handle(event) }
        }

        func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
            let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
            guard !pending.isEmpty else { return nil }
            let records = await MainActor.run { transport?.outgoingRecords(for: pending) ?? [:] }
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { records[$0] }
        }
    }
}
