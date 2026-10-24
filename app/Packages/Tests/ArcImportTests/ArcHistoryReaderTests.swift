import Foundation
import SQLite3
import Testing
import ArcImport

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// Microseconds since 1601, as Chromium stores them.
private func chromiumTime(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
}

/// A folder laid out like Arc's, with a History database per profile.
private func arcFolder(profiles: [String: [(url: String, title: String?, count: Int, date: Date, hidden: Bool)]]) throws -> ArcDataLocation {
    let root = FileManager.default.temporaryDirectory.appending(path: "sela-arc-\(UUID().uuidString)")
    for (profile, rows) in profiles {
        let folder = root.appending(path: "User Data/\(profile)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var db: OpaquePointer?
        sqlite3_open(folder.appending(path: "History").path, &db)
        sqlite3_exec(db, "CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT,url LONGVARCHAR,title LONGVARCHAR,visit_count INTEGER DEFAULT 0 NOT NULL,typed_count INTEGER DEFAULT 0 NOT NULL,last_visit_time INTEGER NOT NULL,hidden INTEGER DEFAULT 0 NOT NULL)", nil, nil, nil)
        for row in rows {
            let title = row.title.map { "'\($0)'" } ?? "''"
            sqlite3_exec(db, "INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('\(row.url)', \(title), \(row.count), \(chromiumTime(row.date)), \(row.hidden ? 1 : 0))", nil, nil, nil)
        }
        sqlite3_close(db)
    }
    return ArcDataLocation(root: root)
}

@Test func readsVisitsNewestFirst() throws {
    let arc = try arcFolder(profiles: ["Default": [
        ("https://a.example.com/", "A", 3, now.addingTimeInterval(-2 * day), false),
        ("https://b.example.com/", "B", 1, now.addingTimeInterval(-1 * day), false),
    ]])
    let visits = readArcHistory(from: arc, since: now.addingTimeInterval(-90 * day))
    #expect(visits.map(\.title) == ["B", "A"])
    #expect(visits.first?.visitCount == 1)
    #expect(abs((visits.first?.lastVisitedAt.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-1 * day).timeIntervalSince1970) < 1)
}

@Test func skipsHiddenOldAndNonWebRows() throws {
    let arc = try arcFolder(profiles: ["Default": [
        ("https://kept.example.com/", "Kept", 1, now, false),
        ("https://hidden.example.com/", "Hidden", 1, now, true),
        ("https://old.example.com/", "Old", 1, now.addingTimeInterval(-100 * day), false),
        ("chrome://settings/", "Settings", 1, now, false),
        ("file:///Users/x/a.html", "File", 1, now, false),
        ("javascript:void(0)", "JS", 1, now, false),
    ]])
    #expect(readArcHistory(from: arc, since: now.addingTimeInterval(-90 * day)).map(\.title) == ["Kept"])
}

@Test func emptyTitlesBecomeNil() throws {
    let arc = try arcFolder(profiles: ["Default": [("https://a.example.com/", nil, 1, now, false)]])
    #expect(readArcHistory(from: arc, since: now.addingTimeInterval(-90 * day)).first?.title == nil)
}

@Test func readsEveryProfile() throws {
    let arc = try arcFolder(profiles: [
        "Default": [("https://a.example.com/", "A", 1, now, false)],
        "Profile 1": [("https://b.example.com/", "B", 1, now.addingTimeInterval(-10), false)],
    ])
    #expect(Set(readArcHistory(from: arc, since: now.addingTimeInterval(-90 * day)).compactMap(\.title)) == ["A", "B"])
}

@Test func missingArcGivesNothing() {
    let arc = ArcDataLocation(root: FileManager.default.temporaryDirectory.appending(path: "sela-no-arc-\(UUID().uuidString)"))
    #expect(readArcHistory(from: arc, since: .distantPast).isEmpty)
}
