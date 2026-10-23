import Foundation
import Observation
import SidebarModel

/// Why the sidebar on disk couldn't be used at launch.
public enum SidebarLoadProblem: Equatable, Sendable {
    /// The file couldn't be read. It was moved to `backupURL` and Brow started with an empty sidebar.
    case corrupt(backupURL: URL)
    /// A newer Brow wrote the file. Brow runs with an empty sidebar and never saves over the file.
    case newerVersion(Int)
}

/// The app's one sidebar, shared by every window. Saves itself shortly after each change.
@MainActor
@Observable
public final class SidebarStore {
    public internal(set) var document: SidebarDocument
    public private(set) var loadProblem: SidebarLoadProblem?
    public private(set) var lastSaveError: String?

    @ObservationIgnored let now: @MainActor () -> Date
    @ObservationIgnored private let fileStore: SidebarDocumentStore
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// Loads the sidebar from `fileStore`. When there's no file yet, uses `firstRunDocument`, or an empty sidebar if it returns nil.
    public init(
        fileStore: SidebarDocumentStore,
        saveDelay: Duration = .milliseconds(500),
        now: @escaping @MainActor () -> Date = { .now },
        firstRunDocument: () -> SidebarDocument?
    ) {
        self.fileStore = fileStore
        self.saveDelay = saveDelay
        self.now = now

        do {
            if let saved = try fileStore.load(now: now()) {
                document = saved
            } else {
                document = firstRunDocument() ?? .empty(now: now())
                hasUnsavedChanges = true
                saveNow()
            }
        } catch SidebarError.unsupportedVersion(let version) {
            document = .empty(now: now())
            loadProblem = .newerVersion(version)
        } catch SidebarError.corruptFile(let backupURL) {
            document = .empty(now: now())
            loadProblem = .corrupt(backupURL: backupURL)
            hasUnsavedChanges = true
            saveNow()
        } catch {
            document = .empty(now: now())
            lastSaveError = error.localizedDescription
        }
    }

    /// Writes unsaved changes now instead of waiting for the delay.
    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges, !isReadOnly else { return }
        do {
            try fileStore.save(document)
            hasUnsavedChanges = false
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    /// Applies a change to the document and schedules a save. Changes that throw leave the document as it was.
    @discardableResult
    func change<Result>(_ body: (inout SidebarDocument) throws -> Result) rethrows -> Result {
        var copy = document
        let result = try body(&copy)
        if copy != document {
            document = copy
            scheduleSave()
        }
        return result
    }

    private var isReadOnly: Bool {
        if case .newerVersion = loadProblem { return true }
        return false
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
