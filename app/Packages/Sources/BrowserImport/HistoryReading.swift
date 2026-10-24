import Foundation
import SQLite3

/// Seconds between 1601-01-01, where Chromium's clock starts, and 1970-01-01.
private let chromiumEpochOffset: Double = 11_644_473_600

/// Chromium stores times as microseconds since 1601-01-01.
public func chromiumDate(microseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - chromiumEpochOffset)
}

public func chromiumMicroseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 + chromiumEpochOffset) * 1_000_000)
}

/// Web pages from a Chromium `History` database visited since `cutoff`, newest first. Hidden rows are left out.
public func readChromiumHistory(at file: URL, since cutoff: Date) throws -> [ImportedVisit] {
    let sql = """
        SELECT url, title, visit_count, last_visit_time FROM urls
        WHERE hidden = 0 AND last_visit_time >= ? AND (url LIKE 'http://%' OR url LIKE 'https://%')
        """
    return try readHistory(at: file, sql: sql, since: chromiumMicroseconds(cutoff)) { chromiumDate(microseconds: $0) }
}

/// Web pages from Safari's `History.db` visited since `cutoff`, newest first, each with the title of its latest visit.
/// Safari stores times as seconds since 2001-01-01.
public func readSafariHistory(at file: URL, since cutoff: Date) throws -> [ImportedVisit] {
    // SQLite takes the bare `title` column from the row holding the MAX.
    let sql = """
        SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) FROM history_items i
        JOIN history_visits v ON v.history_item = i.id
        WHERE v.visit_time >= ? AND (i.url LIKE 'http://%' OR i.url LIKE 'https://%')
        GROUP BY i.id
        """
    return try readHistory(at: file, sql: sql, since: Int64(cutoff.timeIntervalSinceReferenceDate.rounded(.down))) {
        Date(timeIntervalSinceReferenceDate: Double($0))
    }
}

/// Runs `sql` on a copy of the database. The browser holds its database locked while it runs, so the file and its
/// write-ahead log are copied to a temporary folder first and the copy is opened read-only.
private func readHistory(at file: URL, sql: String, since: Int64, date: (Int64) -> Date) throws -> [ImportedVisit] {
    guard let copy = try copyDatabase(file) else { return [] }
    defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw BrowserImportError.malformed("history: \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open")")
    }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw BrowserImportError.malformed("history: \(String(cString: sqlite3_errmsg(db)))")
    }
    sqlite3_bind_int64(statement, 1, since)

    var visits: [ImportedVisit] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let text = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: text)) else { continue }
        let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        visits.append(ImportedVisit(
            url: url,
            title: title,
            visitCount: Int(sqlite3_column_int64(statement, 2)),
            lastVisitedAt: date(sqlite3_column_int64(statement, 3))
        ))
    }
    return visits.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
}

/// Copies the database and any `-wal` and `-shm` files beside it into a new temporary folder. Nil when there's no
/// database. A refused read throws `needsFullDiskAccess`.
private func copyDatabase(_ file: URL) throws -> URL? {
    let manager = FileManager.default
    let folder = manager.temporaryDirectory.appending(path: "sela-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let copy = folder.appending(path: file.lastPathComponent)
    do {
        try manager.copyItem(at: file, to: copy)
        for suffix in ["-wal", "-shm"] {
            let companion = URL(fileURLWithPath: file.path + suffix)
            guard manager.fileExists(atPath: companion.path) else { continue }
            try manager.copyItem(at: companion, to: URL(fileURLWithPath: copy.path + suffix))
        }
    } catch {
        try? manager.removeItem(at: folder)
        if isPermissionDenied(error) { throw BrowserImportError.needsFullDiskAccess }
        if !manager.fileExists(atPath: file.path) { return nil }
        throw BrowserImportError.malformed("history: \(error.localizedDescription)")
    }
    return copy
}
