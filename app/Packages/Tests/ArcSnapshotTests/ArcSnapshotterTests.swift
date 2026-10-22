import Foundation
import Testing
import ArcSnapshot

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

private struct Fixture {
    let source: URL
    let destination: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "brow-snapshot-\(UUID().uuidString)")
        source = base.appending(path: "Arc")
        destination = base.appending(path: "Backups")
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appending(path: "User Data/Default/Cache"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appending(path: "User Data/Default/Code Cache/js"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: source.appending(path: "StorableSidebar.json"))
        try Data(repeating: 2, count: 20).write(to: source.appending(path: "User Data/Default/History"))
        try Data(repeating: 3, count: 1000).write(to: source.appending(path: "User Data/Default/Cache/data_0"))
        try Data(repeating: 4, count: 1000).write(to: source.appending(path: "User Data/Default/Code Cache/js/x"))
        try fm.createSymbolicLink(atPath: source.appending(path: "User Data/SingletonLock").path, withDestinationPath: "host-123")
    }

    func snapshotter(running: Bool = false, capacity: Int64 = 1_000_000_000) -> ArcSnapshotter {
        ArcSnapshotter(
            source: source,
            destinationRoot: destination,
            arcVersion: "1.169.0",
            isArcRunning: { running },
            availableCapacity: { _ in capacity }
        )
    }

    var destinationEntries: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
    }
}

private func exists(_ root: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path)
}

private func isSymlink(_ root: URL, _ path: String) -> Bool {
    let attributes = try? FileManager.default.attributesOfItem(atPath: root.appending(path: path).path)
    return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
}

/// Every path under `root` with its size and modification date.
private func listing(_ root: URL) -> [String] {
    let fm = FileManager.default
    let paths = (fm.subpaths(atPath: root.path) ?? []).sorted()
    return paths.map { path in
        let attributes = (try? fm.attributesOfItem(atPath: root.appending(path: path).path)) ?? [:]
        return "\(path) \(attributes[.size] ?? "") \(attributes[.modificationDate] ?? "")"
    }
}

@Test func copiesDataAndSkipsCaches() throws {
    let fixture = try Fixture()
    let result = try fixture.snapshotter().run(now: fixedNow)
    #expect(result.folderURL.lastPathComponent == "Arc-snapshot-20270115-080000")
    #expect(exists(result.folderURL, "StorableSidebar.json"))
    #expect(exists(result.folderURL, "User Data/Default/History"))
    #expect(!exists(result.folderURL, "User Data/Default/Cache"))
    #expect(!exists(result.folderURL, "User Data/Default/Code Cache"))
    #expect(isSymlink(result.folderURL, "User Data/SingletonLock"))
    #expect(result.manifest.fileCount == 2)
    #expect(result.manifest.totalBytes == 30)
}

@Test func writesManifestFile() throws {
    let fixture = try Fixture()
    let result = try fixture.snapshotter().run(now: fixedNow)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try Data(contentsOf: result.folderURL.appending(path: "snapshot-manifest.json"))
    let manifest = try decoder.decode(SnapshotManifest.self, from: data)
    #expect(manifest == result.manifest)
    #expect(manifest.arcVersion == "1.169.0")
}

@Test func refusesWhileArcRunning() throws {
    let fixture = try Fixture()
    #expect(throws: ArcSnapshotError.arcIsRunning) {
        try fixture.snapshotter(running: true).run(now: fixedNow)
    }
    #expect(fixture.destinationEntries.isEmpty)
}

@Test func allowWhileRunningOverrides() throws {
    let fixture = try Fixture()
    let result = try fixture.snapshotter(running: true).run(now: fixedNow, allowWhileRunning: true)
    #expect(exists(result.folderURL, "StorableSidebar.json"))
}

@Test func insufficientSpaceFailsBeforeCopying() throws {
    let fixture = try Fixture()
    #expect(throws: ArcSnapshotError.insufficientSpace(needed: 33, available: 20)) {
        try fixture.snapshotter(capacity: 20).run(now: fixedNow)
    }
    #expect(fixture.destinationEntries.isEmpty)
}

@Test func missingSourceThrows() throws {
    let fixture = try Fixture()
    let missing = fixture.source.appending(path: "nope")
    let snapshotter = ArcSnapshotter(
        source: missing,
        destinationRoot: fixture.destination,
        arcVersion: nil,
        isArcRunning: { false },
        availableCapacity: { _ in 1_000_000 }
    )
    #expect(throws: ArcSnapshotError.sourceMissing(missing)) {
        try snapshotter.run(now: fixedNow)
    }
}

@Test func existingSnapshotFolderThrows() throws {
    let fixture = try Fixture()
    let existing = fixture.destination.appending(path: "Arc-snapshot-20270115-080000")
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
    #expect(throws: ArcSnapshotError.destinationExists(existing)) {
        try fixture.snapshotter().run(now: fixedNow)
    }
}

@Test func sourceIsUnchanged() throws {
    let fixture = try Fixture()
    let before = listing(fixture.source)
    _ = try fixture.snapshotter().run(now: fixedNow)
    #expect(listing(fixture.source) == before)
}
