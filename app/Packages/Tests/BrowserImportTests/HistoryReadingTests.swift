import Foundation
import SQLite3
import Testing
import BrowserImport

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-history-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Opens a new database, runs `statements`, and returns the open connection so tests can keep it busy.
private func database(at file: URL, _ statements: [String]) -> OpaquePointer? {
    var db: OpaquePointer?
    sqlite3_open(file.path, &db)
    for statement in statements { sqlite3_exec(db, statement, nil, nil, nil) }
    return db
}

private func chromiumHistory(at file: URL, rows: [(url: String, title: String?, count: Int, date: Date, hidden: Bool)], wal: Bool = false) -> OpaquePointer? {
    database(at: file, (wal ? ["PRAGMA journal_mode = WAL", "PRAGMA wal_autocheckpoint = 0"] : []) + [
        "CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT,url LONGVARCHAR,title LONGVARCHAR,visit_count INTEGER DEFAULT 0 NOT NULL,typed_count INTEGER DEFAULT 0 NOT NULL,last_visit_time INTEGER NOT NULL,hidden INTEGER DEFAULT 0 NOT NULL)",
    ] + rows.map { row in
        "INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('\(row.url)', '\(row.title ?? "")', \(row.count), \(chromiumMicroseconds(row.date)), \(row.hidden ? 1 : 0))"
    })
}

@Test func convertsChromiumTimes() {
    // 1601-01-01 is Chromium's zero, and 1970-01-01 is 11,644,473,600 seconds later.
    #expect(chromiumDate(microseconds: 0) == Date(timeIntervalSince1970: -11_644_473_600))
    #expect(chromiumDate(microseconds: 11_644_473_600_000_000) == Date(timeIntervalSince1970: 0))
    #expect(chromiumDate(microseconds: 13_244_473_600_500_000) == Date(timeIntervalSince1970: 1_600_000_000.5))
    #expect(chromiumMicroseconds(Date(timeIntervalSince1970: 1_600_000_000.5)) == 13_244_473_600_500_000)
}

@Test func readsChromiumHistoryNewestFirstAndSkipsHiddenOldAndNonWebRows() throws {
    let file = try temporaryFolder().appending(path: "History")
    sqlite3_close(chromiumHistory(at: file, rows: [
        ("https://a.example.com/", "A", 3, now.addingTimeInterval(-2 * day), false),
        ("https://b.example.com/", "B", 1, now.addingTimeInterval(-1 * day), false),
        ("https://untitled.example.com/", nil, 1, now.addingTimeInterval(-3 * day), false),
        ("https://hidden.example.com/", "Hidden", 1, now, true),
        ("https://old.example.com/", "Old", 1, now.addingTimeInterval(-100 * day), false),
        ("chrome://settings/", "Settings", 1, now, false),
    ]))
    let visits = try readChromiumHistory(at: file, since: now.addingTimeInterval(-90 * day))
    #expect(visits.map(\.url.host) == ["b.example.com", "a.example.com", "untitled.example.com"])
    #expect(visits.map(\.title) == ["B", "A", nil])
    #expect(visits[1].visitCount == 3)
    #expect(abs(visits[0].lastVisitedAt.timeIntervalSince(now.addingTimeInterval(-day))) < 0.001)
}

@Test func readsChromiumHistoryWhileTheBrowserHoldsItOpen() throws {
    let file = try temporaryFolder().appending(path: "History")
    // The browser's connection stays open, so the newest rows are still only in the write-ahead log.
    let browser = chromiumHistory(at: file, rows: [("https://live.example.com/", "Live", 1, now, false)], wal: true)
    defer { sqlite3_close(browser) }
    #expect(FileManager.default.fileExists(atPath: file.path + "-wal"))

    #expect(try readChromiumHistory(at: file, since: now.addingTimeInterval(-day)).map(\.title) == ["Live"])
}

@Test func readsSafariHistoryWithEachPagesLatestVisit() throws {
    let file = try temporaryFolder().appending(path: "History.db")
    // Safari counts seconds from 2001-01-01.
    func safariTime(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate }
    sqlite3_close(database(at: file, [
        "CREATE TABLE history_items (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, domain_expansion TEXT NULL, visit_count INTEGER NOT NULL)",
        "CREATE TABLE history_visits (id INTEGER PRIMARY KEY AUTOINCREMENT, history_item INTEGER NOT NULL, visit_time REAL NOT NULL, title TEXT NULL, load_successful BOOLEAN NOT NULL DEFAULT 1)",
        "INSERT INTO history_items (id, url, visit_count) VALUES (1, 'https://a.example.com/', 2), (2, 'https://b.example.com/', 1), (3, 'https://old.example.com/', 1), (4, 'file:///tmp/a.html', 1)",
        "INSERT INTO history_visits (history_item, visit_time, title) VALUES (1, \(safariTime(now.addingTimeInterval(-5 * day))), 'A then'), (1, \(safariTime(now.addingTimeInterval(-1 * day))), 'A now')",
        "INSERT INTO history_visits (history_item, visit_time, title) VALUES (2, \(safariTime(now.addingTimeInterval(-2 * day))), NULL)",
        "INSERT INTO history_visits (history_item, visit_time, title) VALUES (3, \(safariTime(now.addingTimeInterval(-100 * day))), 'Old')",
        "INSERT INTO history_visits (history_item, visit_time, title) VALUES (4, \(safariTime(now)), 'File')",
    ]))
    let visits = try readSafariHistory(at: file, since: now.addingTimeInterval(-90 * day))
    #expect(visits.map(\.url.host) == ["a.example.com", "b.example.com"])
    #expect(visits.map(\.title) == ["A now", nil])
    #expect(visits.map(\.visitCount) == [2, 1])
    #expect(abs(visits[0].lastVisitedAt.timeIntervalSince(now.addingTimeInterval(-day))) < 1)
}

@Test func missingHistoryGivesNothing() throws {
    let folder = try temporaryFolder()
    #expect(try readChromiumHistory(at: folder.appending(path: "History"), since: .distantPast).isEmpty)
    #expect(try readSafariHistory(at: folder.appending(path: "History.db"), since: .distantPast).isEmpty)
}

@Test func historyThatIsntADatabaseThrows() throws {
    let file = try temporaryFolder().appending(path: "History")
    try Data("not a database".utf8).write(to: file)
    #expect(throws: BrowserImportError.self) { try readChromiumHistory(at: file, since: .distantPast) }
}
