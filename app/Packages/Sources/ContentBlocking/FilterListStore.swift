import Foundation

/// Downloaded filter lists, saved as `<id>.txt` in one folder. A list is downloaded again once it's older than
/// a day. A download that doesn't look like a filter list, such as a Wi-Fi sign-in page, never replaces a good one.
@MainActor
public final class FilterListStore {
    private let folder: URL
    private let now: @MainActor () -> Date
    private let fetch: @Sendable (URL) async throws -> (Data, Int)
    private var refreshedAt: [String: Date]

    /// `fetch` returns the body and the HTTP status code.
    public init(folder: URL, now: @escaping @MainActor () -> Date = { .now }, fetch: @escaping @Sendable (URL) async throws -> (Data, Int)) {
        self.folder = folder
        self.now = now
        self.fetch = fetch
        let saved = (try? Data(contentsOf: folder.appending(path: Self.refreshFileName))).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }
        refreshedAt = saved ?? [:]
    }

    private static let refreshFileName = "refreshed.json"

    public func text(for list: FilterList) -> String? {
        try? String(contentsOf: fileURL(for: list), encoding: .utf8)
    }

    /// Downloads every list that's missing or older than `maxAge`. Returns true when any list's text changed.
    @discardableResult
    public func refresh(_ lists: [FilterList], maxAge: TimeInterval = 86_400) async -> Bool {
        var changed = false
        for list in lists {
            if text(for: list) != nil, let last = refreshedAt[list.id], now().timeIntervalSince(last) < maxAge { continue }
            guard let (data, status) = try? await fetch(list.url), (200..<300).contains(status),
                  let text = String(data: data, encoding: .utf8), Self.looksLikeFilterList(text)
            else { continue }
            if text != self.text(for: list) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                guard (try? Data(text.utf8).write(to: fileURL(for: list), options: .atomic)) != nil else { continue }
                changed = true
            }
            refreshedAt[list.id] = now()
            saveRefreshTimes()
        }
        return changed
    }

    /// Adblock-style lists start with a header such as `[Adblock Plus 2.0]`.
    static func looksLikeFilterList(_ text: String) -> Bool {
        let firstLine = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return firstLine?.trimmingCharacters(in: .whitespaces).hasPrefix("[Adblock") ?? false
    }

    private func fileURL(for list: FilterList) -> URL {
        folder.appending(path: "\(list.id).txt")
    }

    private func saveRefreshTimes() {
        guard let data = try? JSONEncoder().encode(refreshedAt) else { return }
        try? data.write(to: folder.appending(path: Self.refreshFileName), options: .atomic)
    }
}
