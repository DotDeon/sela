import Foundation
import SQLite3

/// A visited page.
public struct HistoryEntry: Equatable, Sendable {
    public var url: URL
    public var title: String?
    public var visitCount: Int
    public var lastVisitedAt: Date

    public init(url: URL, title: String?, visitCount: Int, lastVisitedAt: Date) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisitedAt = lastVisitedAt
    }
}

public struct HistoryError: Error, CustomStringConvertible {
    public let description: String
}

/// Visited web pages, kept for 90 days in a SQLite file.
@MainActor
public final class HistoryStore {
    static let maximumAge: TimeInterval = 90 * 24 * 60 * 60

    nonisolated(unsafe) private var db: OpaquePointer?
    private let now: @MainActor () -> Date

    public init(fileURL: URL, now: @escaping @MainActor () -> Date = { .now }) throws {
        self.now = now
        guard sqlite3_open(fileURL.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw HistoryError(description: "Couldn't open history: \(message)")
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA secure_delete = ON")
        try registerFold()
        try execute("CREATE TABLE IF NOT EXISTS visits (url TEXT PRIMARY KEY, title TEXT, visit_count INTEGER NOT NULL, last_visited REAL NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS visits_by_time ON visits (last_visited)")
        run("DELETE FROM visits WHERE last_visited < ?", [.double(now().addingTimeInterval(-Self.maximumAge).timeIntervalSince1970)])
    }

    deinit {
        sqlite3_close(db)
    }

    /// `~/Library/Application Support/Sela/History.sqlite`. Creates the `Sela` folder if needed.
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appending(path: "Sela", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "History.sqlite")
    }

    /// Counts a visit to a web page. A nil title keeps the title already stored. Non-web addresses are ignored.
    public func recordVisit(url: URL, title: String?) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        run("""
            INSERT INTO visits (url, title, visit_count, last_visited) VALUES (?, ?, 1, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = COALESCE(excluded.title, visits.title),
                visit_count = visits.visit_count + 1,
                last_visited = excluded.last_visited
            """, [.text(url.absoluteString), title.map(Value.text) ?? .null, .double(now().timeIntervalSince1970)])
    }

    /// Pages whose address or title contains every word of `query`, ignoring case and accents, most recent first.
    /// A blank query returns the most recent.
    public func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let conditions = words.map { _ in "sela_fold(url || ' ' || COALESCE(title, '')) LIKE ? ESCAPE '\\'" }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT url, title, visit_count, last_visited FROM visits \(whereClause) ORDER BY last_visited DESC LIMIT ?"
        let values = words.map { Value.text("%\(escapeLike($0))%") } + [.int(limit)]

        var results: [HistoryEntry] = []
        withStatement(sql, values) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let urlText = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: urlText)) else { continue }
                let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }
                results.append(HistoryEntry(
                    url: url,
                    title: title,
                    visitCount: Int(sqlite3_column_int64(statement, 2)),
                    lastVisitedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                ))
            }
        }
        return results
    }

    /// Merges visits from elsewhere, such as Arc, in one transaction. Each page keeps the larger visit count and the
    /// later visit, so importing twice changes nothing, and an existing title wins. Returns how many rows changed.
    @discardableResult
    public func importVisits(_ visits: [HistoryEntry]) -> Int {
        let before = sqlite3_total_changes(db)
        run("BEGIN", [])
        for visit in visits {
            guard let scheme = visit.url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { continue }
            run("""
                INSERT INTO visits (url, title, visit_count, last_visited) VALUES (?, ?, ?, ?)
                ON CONFLICT(url) DO UPDATE SET
                    title = COALESCE(visits.title, excluded.title),
                    visit_count = max(visits.visit_count, excluded.visit_count),
                    last_visited = max(visits.last_visited, excluded.last_visited)
                WHERE visits.title IS NOT excluded.title AND visits.title IS NULL
                    OR visits.visit_count < excluded.visit_count
                    OR visits.last_visited < excluded.last_visited
                """, [.text(visit.url.absoluteString), visit.title.map(Value.text) ?? .null, .int(visit.visitCount), .double(visit.lastVisitedAt.timeIntervalSince1970)])
        }
        run("COMMIT", [])
        return Int(sqlite3_total_changes(db) - before)
    }

    /// Deletes every visit and rewrites the files, so nothing of the old history stays on disk.
    public func clear() {
        run("DELETE FROM visits", [])
        try? execute("VACUUM")
        try? execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    // MARK: SQLite

    enum Value {
        case text(String)
        case double(Double)
        case int(Int)
        case null
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Adds `sela_fold(text)` to SQL, which lowercases and strips accents the same way as `fold`.
    /// SQLite's own `LIKE` only ignores case for ASCII letters.
    private func registerFold() throws {
        let result = sqlite3_create_function_v2(db, "sela_fold", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, arguments in
            guard let argument = arguments?[0], let text = sqlite3_value_text(argument) else {
                sqlite3_result_null(context)
                return
            }
            let folded = HistoryStore.fold(String(cString: text))
            sqlite3_result_text(context, folded, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }, nil, nil, nil)
        guard result == SQLITE_OK else { throw HistoryError(description: String(cString: sqlite3_errmsg(db))) }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryError(description: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func run(_ sql: String, _ values: [Value]) {
        withStatement(sql, values) { statement in
            _ = sqlite3_step(statement)
        }
    }

    private func withStatement(_ sql: String, _ values: [Value], _ body: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .double(let number): sqlite3_bind_double(statement, index, number)
            case .int(let number): sqlite3_bind_int64(statement, index, Int64(number))
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        body(statement)
    }

    /// Escapes `%`, `_` and `\` so they match literally in a `LIKE ... ESCAPE '\'` pattern.
    private func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
