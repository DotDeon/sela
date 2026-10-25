import Foundation
import Observation
import Sidebar
import SidebarModel

/// Keeps the sidebar in step with iCloud. Sidebar.json stays the sidebar; this watches it for changes to send,
/// merges what arrives, and holds the state the Settings tab shows. Off until the person turns it on.
@MainActor
@Observable
public final class CloudSyncModel {
    public static let enabledKey = "CloudSyncEnabled"

    /// A merge that would take away most of the sidebar, waiting for the person's say-so.
    public struct PendingRemoval: Equatable, Sendable {
        public var removedItems: Int
        public var localItems: Int
        var records: [RecordKey: IncomingRecord]
    }

    public private(set) var isEnabled: Bool
    public private(set) var accountStatus: AccountStatus?
    public private(set) var lastSyncAt: Date?
    public private(set) var problem: SyncProblem?
    public private(set) var isSyncing = false
    public private(set) var pendingRemoval: PendingRemoval?
    public let deviceName: String

    @ObservationIgnored private let sidebar: SidebarStore
    @ObservationIgnored private let transport: any SyncTransport
    @ObservationIgnored private let ledgerStore: SyncLedgerStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let compareDelay: Duration
    @ObservationIgnored private(set) var ledger: SyncLedger
    @ObservationIgnored private var pendingCompare: Task<Void, Never>?

    public init(
        sidebar: SidebarStore,
        transport: any SyncTransport,
        ledgerStore: SyncLedgerStore,
        defaults: UserDefaults = .standard,
        deviceName: String = Host.current().localizedName ?? "This Mac",
        compareDelay: Duration = .seconds(1),
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.sidebar = sidebar
        self.transport = transport
        self.ledgerStore = ledgerStore
        self.defaults = defaults
        self.deviceName = deviceName
        self.compareDelay = compareDelay
        self.now = now
        ledger = ledgerStore.load()
        lastSyncAt = ledger.lastSyncAt
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        transport.delegate = self
        if isEnabled { start() }
    }

    /// Turning sync off leaves what's in iCloud as it is, and turning it on again carries on from there.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            start()
        } else {
            pendingCompare?.cancel()
            transport.stop()
            problem = nil
        }
    }

    public func syncNow() async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        compareNow()
        await refreshAccountStatus()
        if accountStatus == .available { await transport.syncNow() }
        isSyncing = false
    }

    public func refreshAccountStatus() async {
        guard isEnabled else { return }
        let status = await transport.accountStatus()
        accountStatus = status
        switch status {
        case .noAccount: problem = .signedOut
        case .restricted: problem = .restricted
        case .available: if problem == .signedOut || problem == .restricted { problem = nil }
        case .temporarilyUnavailable, .couldNotDetermine: break
        }
    }

    /// Applies or turns down the removal waiting in `pendingRemoval`. Turning it down keeps this Mac's items and
    /// sends them up again, so they come back on the other Macs too.
    public func resolvePendingRemoval(applying: Bool) {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        if applying {
            apply(Array(pending.records.values), force: true)
            return
        }
        let kept = pending.records.values.filter { $0.record.isTombstone }.map(\.record.key)
        apply(pending.records.values.filter { !$0.record.isTombstone }, force: true)
        ledger.markChanged(kept, tag: tag())
        saveLedger()
        transport.queueSaves(kept)
    }

    // MARK: Watching the sidebar

    private func start() {
        transport.start(state: ledger.engineState)
        compare()
        transport.queueSaves(Array(ledger.pending))
        Task { await refreshAccountStatus() }
        observe()
    }

    /// Runs after any change to the sidebar while sync is on. Reading `isEnabled` keeps the chain alive while off,
    /// so turning sync back on resumes it.
    private func observe() {
        withObservationTracking {
            guard isEnabled else { return }
            _ = sidebar.document
            scheduleCompare()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func scheduleCompare() {
        pendingCompare?.cancel()
        let delay = compareDelay
        pendingCompare = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.compareNow()
        }
    }

    /// Finds what changed in the sidebar since the last compare and queues it. The first compare ever tags
    /// everything as very old, so a sidebar already in iCloud wins over a Mac that's only just joined, and
    /// what this Mac alone has still goes up.
    func compareNow() {
        transport.queueSaves(compare())
    }

    @discardableResult
    private func compare() -> [RecordKey] {
        pendingCompare?.cancel()
        pendingCompare = nil
        let first = ledger.known.isEmpty
        let tag = first ? ChangeTag(date: .distantPast, deviceID: ledger.deviceID, deviceName: deviceName) : tag()
        let changed = ledger.noteLocal(SidebarRecords.bodies(of: sidebar.document), tag: tag)
        if !changed.isEmpty { saveLedger() }
        return changed
    }

    private func tag() -> ChangeTag {
        ChangeTag(date: now(), deviceID: ledger.deviceID, deviceName: deviceName)
    }

    private func saveLedger() {
        try? ledgerStore.save(ledger)
    }

    // MARK: Merging

    /// Merges records into the sidebar. A merge that would take away most of the synced items waits for the
    /// person instead, unless `force`.
    func apply(_ records: [IncomingRecord], force: Bool = false) {
        guard !records.isEmpty else { return }
        var incoming = pendingRemoval?.records ?? [:]
        for record in records {
            if let earlier = incoming[record.record.key], earlier.record.tag >= record.record.tag { continue }
            incoming[record.record.key] = record
        }
        let result = SyncMerge.merge(incoming.values.map(\.record), into: sidebar.document, known: ledger.tags, localDeviceName: deviceName, now: now())
        if result.removesMostItems, !force {
            pendingRemoval = PendingRemoval(removedItems: result.removedItems, localItems: result.localItems, records: incoming)
            return
        }
        pendingRemoval = nil
        if (try? result.document.validate()) == nil {
            problem = .other("The sidebar from iCloud didn't hold together, so this Mac kept its own.")
            return
        }
        var systemFields: [RecordKey: Data] = [:]
        for (key, record) in incoming { systemFields[key] = record.systemFields }
        ledger.noteApplied(result.applied, systemFields: systemFields)
        sidebar.edit { $0 = result.document }
        // The repair may have changed records beyond what arrived, and those go up like any other edit.
        compareNow()
        saveLedger()
    }
}

extension CloudSyncModel: SyncTransportDelegate {
    public func outgoingRecords(for keys: [RecordKey]) -> [OutgoingRecord] {
        keys.compactMap { ledger.outgoing($0) }
    }

    public func transport(_ transport: any SyncTransport, fetched records: [IncomingRecord]) {
        apply(records)
    }

    public func transport(_ transport: any SyncTransport, saved key: RecordKey, systemFields: Data) {
        ledger.noteSaved(key, systemFields: systemFields)
        saveLedger()
    }

    public func transport(_ transport: any SyncTransport, conflict key: RecordKey, server: IncomingRecord) {
        ledger.known[key]?.systemFields = server.systemFields
        apply([server])
        if let mine = ledger.known[key], mine.tag > server.record.tag {
            ledger.pending.insert(key)
            saveLedger()
            transport.queueSaves([key])
        }
    }

    public func transport(_ transport: any SyncTransport, lostServerCopyOf key: RecordKey) {
        ledger.known[key]?.systemFields = nil
        guard ledger.known[key] != nil else { return }
        ledger.pending.insert(key)
        saveLedger()
        transport.queueSaves([key])
    }

    public func transport(_ transport: any SyncTransport, finishedWith problem: SyncProblem?) {
        if let problem {
            self.problem = problem
            return
        }
        if self.problem?.pausesSync == false { self.problem = nil }
        lastSyncAt = now()
        ledger.lastSyncAt = lastSyncAt
        saveLedger()
    }

    public func transport(_ transport: any SyncTransport, accountChanged change: AccountChange) {
        switch change {
        case .signedOut:
            problem = .signedOut
            accountStatus = .noAccount
            ledger.forgetServer()
            saveLedger()
        case .signedIn, .switchedAccounts:
            // Another account's records aren't this sidebar's. Start over with this account.
            problem = nil
            accountStatus = .available
            ledger.forgetServer()
            saveLedger()
            transport.stop()
            transport.start(state: nil)
            transport.queueSaves(Array(ledger.pending))
        }
    }

    public func transport(_ transport: any SyncTransport, stateChanged state: Data) {
        ledger.engineState = state
        saveLedger()
    }

    public func transportZoneWasReset(_ transport: any SyncTransport) {
        ledger.forgetServer()
        saveLedger()
        transport.stop()
        transport.start(state: nil)
        transport.queueSaves(Array(ledger.pending))
    }
}
