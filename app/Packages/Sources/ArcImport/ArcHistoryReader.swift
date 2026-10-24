import Foundation
import SQLite3

/// A page from Arc's history.
public struct ArcHistoryVisit: Equatable, Sendable {
    public let url: URL
    public let title: String?
    public let visitCount: Int
    public let lastVisitedAt: Date

    public init(url: URL, title: String?, visitCount: Int, lastVisitedAt: Date) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisitedAt = lastVisitedAt
    }
}

/// Seconds between 1601-01-01, where Chromium's clock starts, and 1970-01-01.
private let chromiumEpochOffset: Double = 11_644_473_600

/// Web pages from every Arc profile's history visited since `cutoff`, newest first. Each `History` database is
/// opened read-only and immutable, so a running Arc isn't disturbed. Hidden rows and non-web addresses are left out,
/// and unreadable or missing files are skipped.
public func readArcHistory(from location: ArcDataLocation, since cutoff: Date) -> [ArcHistoryVisit] {
    let since = Int64((cutoff.timeIntervalSince1970 + chromiumEpochOffset) * 1_000_000)
    let visits = location.historyFileURLs.flatMap { readHistory(at: $0, since: since) }
    return visits.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
}

private func readHistory(at file: URL, since: Int64) -> [ArcHistoryVisit] {
    var components = URLComponents()
    components.scheme = "file"
    components.path = file.path
    components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
    guard let uri = components.string else { return [] }

    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return [] }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    let sql = "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 AND last_visit_time >= ? AND (url LIKE 'http://%' OR url LIKE 'https://%')"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    sqlite3_bind_int64(statement, 1, since)

    var visits: [ArcHistoryVisit] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let text = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: text)) else { continue }
        let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let seconds = Double(sqlite3_column_int64(statement, 3)) / 1_000_000 - chromiumEpochOffset
        visits.append(ArcHistoryVisit(url: url, title: title, visitCount: Int(sqlite3_column_int64(statement, 2)), lastVisitedAt: Date(timeIntervalSince1970: seconds)))
    }
    return visits
}
