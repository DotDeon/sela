import Foundation
import Testing
@testable import SidebarModel

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "sela-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func loadReturnsNilWhenFileMissing() throws {
    let dir = try makeTempDirectory()
    let store = SidebarDocumentStore(fileURL: dir.appending(path: "Sidebar.json"))
    #expect(try store.load(now: now) == nil)
}

@Test func saveThenLoadRoundTrips() throws {
    let dir = try makeTempDirectory()
    let store = SidebarDocumentStore(fileURL: dir.appending(path: "Sidebar.json"))
    let doc = SidebarDocument.empty(now: now)
    try store.save(doc)
    #expect(try store.load(now: now) == doc)
}

@Test func saveWritesSortedPrettyJSON() throws {
    let dir = try makeTempDirectory()
    let url = dir.appending(path: "Sidebar.json")
    let doc = SidebarDocument.empty(now: now)
    try SidebarDocumentStore(fileURL: url).save(doc)

    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("\"version\" : \(SidebarDocument.currentVersion)"))

    let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    let ids = (json["items"] as! [[String: Any]]).map { $0["id"] as! String }
    #expect(ids == ids.sorted())
    #expect(ids.count == 3)
}

@Test func corruptFileIsMovedAsideNotOverwritten() throws {
    let dir = try makeTempDirectory()
    let url = dir.appending(path: "Sidebar.json")
    try Data("{ not json".utf8).write(to: url)
    let store = SidebarDocumentStore(fileURL: url)
    let backup = dir.appending(path: "Sidebar.corrupt-20270115-080000.json")
    #expect(throws: SidebarError.corruptFile(backupURL: backup)) {
        try store.load(now: now)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(try String(contentsOf: backup, encoding: .utf8) == "{ not json")
}

@Test func futureVersionThrowsAndLeavesFileInPlace() throws {
    let dir = try makeTempDirectory()
    let url = dir.appending(path: "Sidebar.json")
    let future = SidebarDocument.currentVersion + 1
    try Data(#"{ "version": \#(future), "spaces": [], "items": [] }"#.utf8).write(to: url)
    let store = SidebarDocumentStore(fileURL: url)
    #expect(throws: SidebarError.unsupportedVersion(future)) {
        try store.load(now: now)
    }
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func structurallyInvalidFileIsTreatedAsCorrupt() throws {
    let dir = try makeTempDirectory()
    let url = dir.appending(path: "Sidebar.json")
    let broken = SidebarDocument(version: 1, spaces: [], favoritesContainerID: "missing", items: [])
    try JSONEncoder().encode(broken).write(to: url)
    let backup = dir.appending(path: "Sidebar.corrupt-20270115-080000.json")
    #expect(throws: SidebarError.corruptFile(backupURL: backup)) {
        try SidebarDocumentStore(fileURL: url).load(now: now)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(FileManager.default.fileExists(atPath: backup.path))
}
