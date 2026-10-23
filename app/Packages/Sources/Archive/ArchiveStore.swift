import Foundation
import Observation

/// Archived tabs, newest first, saved to `Archive.json`. Keeps 30 days and at most 1,000 entries.
@MainActor
@Observable
public final class ArchiveStore {
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    static let maximumCount = 1000

    public private(set) var entries: [ArchiveEntry] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(fileURL: URL, now: @escaping @MainActor () -> Date = { .now }) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    /// `~/Library/Application Support/Brow/Archive.json`. Creates the `Brow` folder if needed.
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appending(path: "Brow", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Archive.json")
    }

    public func add(_ newEntries: [ArchiveEntry]) {
        guard !newEntries.isEmpty else { return }
        entries = pruned(entries + newEntries)
        save()
    }

    @discardableResult
    public func remove(_ id: UUID) -> ArchiveEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = entries.remove(at: index)
        save()
        return entry
    }

    /// Entries whose title or address contains every word of `query`, ignoring case and accents.
    /// A blank query returns everything.
    public func search(_ query: String) -> [ArchiveEntry] {
        let words = Self.fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let text = Self.fold("\(entry.title ?? "") \(entry.url?.absoluteString ?? "")")
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Storage

    private func pruned(_ list: [ArchiveEntry]) -> [ArchiveEntry] {
        let cutoff = now().addingTimeInterval(-Self.maximumAge)
        return Array(list.filter { $0.archivedAt >= cutoff }.sorted { $0.archivedAt > $1.archivedAt }.prefix(Self.maximumCount))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = pruned(try Self.decoder.decode([ArchiveEntry].self, from: data))
        } catch {
            moveCorruptFileAside()
        }
    }

    private func save() {
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func moveCorruptFileAside() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = fileURL.deletingLastPathComponent().appending(path: "Archive.corrupt-\(formatter.string(from: now())).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
