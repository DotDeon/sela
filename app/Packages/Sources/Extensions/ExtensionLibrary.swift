import BrowserEngine
import Foundation
import Observation

/// The extensions the user installed: their files, whether each is on, and what each may do.
/// Copies each extension into Sela's own folder, so it keeps working if the original moves.
@MainActor
@Observable
public final class ExtensionLibrary {
    public struct Entry: Identifiable {
        public var record: ExtensionRecord
        /// The running extension, or nil while it's off or failed to start.
        public var loaded: (any BrowserExtension)?
        /// Why it didn't start, in the engine's words.
        public var problem: String?
        public var id: String { record.id }
    }

    public enum InstallError: LocalizedError, Equatable {
        case unsupported
        case noManifest
        case unreadableArchive

        public var errorDescription: String? {
            switch self {
            case .unsupported: "Extensions need macOS 15.4 or later."
            case .noManifest: "There's no manifest.json in it, so it isn't a Web Extension."
            case .unreadableArchive: "The zip file couldn't be opened."
            }
        }
    }

    public private(set) var entries: [Entry] = []
    /// Why the saved list couldn't be read. While set, nothing is saved, so the file stays as it was.
    public private(set) var loadProblem: ExtensionStore.LoadError?

    @ObservationIgnored private let engine: any ExtensionEngine
    @ObservationIgnored private let store: ExtensionStore
    @ObservationIgnored private let unzip: @Sendable (URL, URL) async throws -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let makeID: @MainActor () -> String

    public init(engine: any ExtensionEngine, store: ExtensionStore,
                unzip: @escaping @Sendable (URL, URL) async throws -> Void = ExtensionSource.unzip(_:into:),
                now: @escaping @MainActor () -> Date = { .now },
                makeID: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }) {
        self.engine = engine
        self.store = store
        self.unzip = unzip
        self.now = now
        self.makeID = makeID
        engine.onExtensionPermissionsChanged = { [weak self] id, permissions in
            self?.update(id) { $0.permissions = permissions }
        }
    }

    public var isSupported: Bool { engine.supportsExtensions }

    /// The extensions that are on and running, in the order they were installed.
    public var running: [any BrowserExtension] {
        entries.compactMap { $0.record.isEnabled ? $0.loaded : nil }
    }

    /// Reads the saved list and starts the extensions that are on.
    public func start() async {
        guard engine.supportsExtensions else { return }
        do {
            entries = try store.load().map { Entry(record: $0) }
        } catch {
            loadProblem = error
            return
        }
        for entry in entries where entry.record.isEnabled {
            await load(entry.id)
        }
    }

    /// Installs the extension in a folder or `.zip`, after `confirm` says yes to what it asks for.
    /// An extension with the same name as one already installed replaces it and keeps its data and permissions,
    /// and `confirm` is only asked when the new version wants more. Returns nil when `confirm` said no.
    @discardableResult
    public func install(from source: URL, confirm: @MainActor (ExtensionDetails) async -> Bool) async throws -> ExtensionRecord? {
        guard engine.supportsExtensions else { throw InstallError.unsupported }
        let fileManager = FileManager.default
        let staging = store.folder.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let unpacked = staging.appending(path: "content", directoryHint: .isDirectory)
        if ExtensionSource.isArchive(source) {
            try await unzip(source, unpacked)
        } else {
            try fileManager.copyItem(at: source, to: unpacked)
        }
        guard let root = ExtensionSource.manifestFolder(in: unpacked) else { throw InstallError.noManifest }
        let details = try await engine.readExtension(at: root)

        let existing = entries.first { $0.record.name == details.name }?.record
        let kept = existing?.permissions ?? .none
        let wanted = kept.ungranted(in: details)
        if existing == nil || !wanted.permissions.isEmpty || !wanted.matchPatterns.isEmpty {
            guard await confirm(details) else { return nil }
        }

        let id = existing?.id ?? makeID()
        if existing != nil { engine.unloadExtension(id: id) }
        let destination = store.contentFolder(for: id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: root, to: destination)

        let record = ExtensionRecord(
            id: id,
            name: details.name,
            version: details.version,
            isEnabled: existing?.isEnabled ?? true,
            installedAt: existing?.installedAt ?? now(),
            permissions: kept.granting(details.requestedPermissions, matchPatterns: details.requestedMatchPatterns)
        )
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index] = Entry(record: record)
        } else {
            entries.append(Entry(record: record))
        }
        save()
        if record.isEnabled { await load(id) }
        return record
    }

    public func setEnabled(_ enabled: Bool, for id: String) async {
        guard let entry = entries.first(where: { $0.id == id }), entry.record.isEnabled != enabled else { return }
        update(id) { $0.isEnabled = enabled }
        if enabled {
            await load(id)
        } else {
            engine.unloadExtension(id: id)
            setLoaded(nil, problem: nil, for: id)
        }
    }

    /// Turns the extension off and deletes its files.
    public func remove(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        engine.unloadExtension(id: id)
        try? FileManager.default.removeItem(at: store.contentFolder(for: id))
        entries.removeAll { $0.id == id }
        save()
    }

    private func load(_ id: String) async {
        guard let record = entries.first(where: { $0.id == id })?.record else { return }
        do {
            let loaded = try await engine.loadExtension(id: id, at: store.contentFolder(for: id), permissions: record.permissions.removingExpired(at: now()))
            // It may have been turned off or removed while it started.
            guard entries.first(where: { $0.id == id })?.record.isEnabled == true else {
                engine.unloadExtension(id: id)
                return
            }
            setLoaded(loaded, problem: nil, for: id)
            if loaded.details.name != record.name || loaded.details.version != record.version {
                update(id) {
                    $0.name = loaded.details.name
                    $0.version = loaded.details.version
                }
            }
        } catch {
            setLoaded(nil, problem: error.localizedDescription, for: id)
        }
    }

    private func setLoaded(_ loaded: (any BrowserExtension)?, problem: String?, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].loaded = loaded
        entries[index].problem = problem
    }

    private func update(_ id: String, _ change: (inout ExtensionRecord) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index].record)
        save()
    }

    private func save() {
        guard loadProblem == nil else { return }
        try? store.save(entries.map(\.record))
    }
}
