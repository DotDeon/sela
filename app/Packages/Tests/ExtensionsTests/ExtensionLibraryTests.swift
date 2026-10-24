import BrowserEngine
import Extensions
import FakeEngine
import Foundation
import Testing

/// A folder holding an extension with the given manifest, ready to install.
private func makeSource(name: String, version: String = "1.0", permissions: [String] = [], nested: Bool = false) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "sela-source-\(UUID().uuidString)", directoryHint: .isDirectory)
    let folder = nested ? root.appending(path: "inner", directoryHint: .isDirectory) : root
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifest: [String: Any] = ["manifest_version": 3, "name": name, "version": version, "permissions": permissions]
    try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
    return root
}

@MainActor
private func makeLibrary(engine: FakeEngine = FakeEngine(), folder: URL? = nil) -> (ExtensionLibrary, FakeEngine, ExtensionStore) {
    let store = ExtensionStore(folder: folder ?? FileManager.default.temporaryDirectory.appending(path: "sela-library-\(UUID().uuidString)", directoryHint: .isDirectory))
    var count = 0
    let library = ExtensionLibrary(engine: engine, store: store, now: { Date(timeIntervalSince1970: 1_800_000_000) }) {
        count += 1
        return "ext-\(count)"
    }
    return (library, engine, store)
}

@MainActor @Test func installingCopiesGrantsAndStarts() async throws {
    let (library, engine, store) = makeLibrary()
    var asked: [ExtensionDetails] = []
    let source = try makeSource(name: "Dark Reader", permissions: ["storage", "<all_urls>"])
    let record = try await library.install(from: source) { details in
        asked.append(details)
        return true
    }
    #expect(asked.map(\.name) == ["Dark Reader"])
    #expect(record?.id == "ext-1")
    #expect(record?.permissions.granted == ["storage": .distantFuture])
    #expect(record?.permissions.grantedMatchPatterns == ["<all_urls>": .distantFuture])
    #expect(FileManager.default.fileExists(atPath: store.contentFolder(for: "ext-1").appending(path: "manifest.json").path))
    #expect(engine.loadedExtensions["ext-1"]?.permissions == record?.permissions)
    #expect(library.running.map(\.id) == ["ext-1"])
    #expect(try store.load() == [record!])
}

@MainActor @Test func decliningInstallsNothing() async throws {
    let (library, engine, store) = makeLibrary()
    let record = try await library.install(from: try makeSource(name: "Nope")) { _ in false }
    #expect(record == nil)
    #expect(library.entries.isEmpty)
    #expect(engine.loadedExtensions.isEmpty)
    #expect(try store.load() == [])
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
    #expect(leftovers.isEmpty)
}

@MainActor @Test func aFolderInsideTheSourceIsFound() async throws {
    let (library, _, _) = makeLibrary()
    let record = try await library.install(from: try makeSource(name: "Zipped", nested: true)) { _ in true }
    #expect(record?.name == "Zipped")
}

@MainActor @Test func aFolderWithoutAManifestIsRefused() async throws {
    let (library, _, _) = makeLibrary()
    let empty = FileManager.default.temporaryDirectory.appending(path: "sela-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    await #expect(throws: ExtensionLibrary.InstallError.noManifest) {
        try await library.install(from: empty) { _ in true }
    }
}

@MainActor @Test func installingTheSameExtensionAgainUpdatesIt() async throws {
    let (library, engine, _) = makeLibrary()
    try await library.install(from: try makeSource(name: "Bitwarden", version: "1.0", permissions: ["storage"])) { _ in true }
    var askedAgain = false
    try await library.install(from: try makeSource(name: "Bitwarden", version: "1.1", permissions: ["storage"])) { _ in
        askedAgain = true
        return true
    }
    #expect(!askedAgain)
    #expect(library.entries.map(\.record.version) == ["1.1"])
    #expect(library.entries.map(\.id) == ["ext-1"])
    #expect(engine.loadedExtensions["ext-1"]?.details.version == "1.1")
}

@MainActor @Test func anUpdateWantingMoreAsksAgain() async throws {
    let (library, _, _) = makeLibrary()
    try await library.install(from: try makeSource(name: "Bitwarden", permissions: ["storage"])) { _ in true }
    var askedAgain = false
    let record = try await library.install(from: try makeSource(name: "Bitwarden", version: "2.0", permissions: ["storage", "tabs"])) { _ in
        askedAgain = true
        return true
    }
    #expect(askedAgain)
    #expect(record?.permissions.granted.keys.sorted() == ["storage", "tabs"])
}

@MainActor @Test func turningOffStopsItAndIsSaved() async throws {
    let (library, engine, store) = makeLibrary()
    try await library.install(from: try makeSource(name: "uBlock Origin")) { _ in true }
    await library.setEnabled(false, for: "ext-1")
    #expect(engine.loadedExtensions.isEmpty)
    #expect(library.running.isEmpty)
    #expect(try store.load().map(\.isEnabled) == [false])
    await library.setEnabled(true, for: "ext-1")
    #expect(library.running.map(\.id) == ["ext-1"])
}

@MainActor @Test func removingDeletesItsFiles() async throws {
    let (library, engine, store) = makeLibrary()
    try await library.install(from: try makeSource(name: "uBlock Origin")) { _ in true }
    library.remove("ext-1")
    #expect(library.entries.isEmpty)
    #expect(engine.loadedExtensions.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.contentFolder(for: "ext-1").path))
    #expect(try store.load() == [])
}

@MainActor @Test func startLoadsOnlyTheOnesThatAreOn() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    let (first, _, _) = makeLibrary(folder: folder)
    try await first.install(from: try makeSource(name: "One")) { _ in true }
    try await first.install(from: try makeSource(name: "Two")) { _ in true }
    await first.setEnabled(false, for: "ext-2")

    let (second, engine, _) = makeLibrary(folder: folder)
    await second.start()
    #expect(second.entries.map(\.record.name) == ["One", "Two"])
    #expect(engine.loadedExtensions.keys.sorted() == ["ext-1"])
}

@MainActor @Test func aFailedStartIsShown() async throws {
    let engine = FakeEngine()
    let (library, _, _) = makeLibrary(engine: engine)
    engine.extensionLoadFailure = "Broken background script"
    try await library.install(from: try makeSource(name: "Broken")) { _ in true }
    #expect(library.entries.first?.loaded == nil)
    #expect(library.entries.first?.problem != nil)
    #expect(library.running.isEmpty)
}

@MainActor @Test func permissionChangesAreSaved() async throws {
    let (library, engine, store) = makeLibrary()
    try await library.install(from: try makeSource(name: "Bitwarden")) { _ in true }
    let changed = ExtensionPermissions(grantedMatchPatterns: ["*://vault.example/*": .distantFuture])
    engine.changePermissions(of: "ext-1", to: changed)
    #expect(try store.load().first?.permissions == changed)
}

@MainActor @Test func olderSystemsInstallNothing() async throws {
    let engine = FakeEngine()
    engine.extensionsSupported = false
    let (library, _, _) = makeLibrary(engine: engine)
    #expect(!library.isSupported)
    await #expect(throws: ExtensionLibrary.InstallError.unsupported) {
        try await library.install(from: try makeSource(name: "Any")) { _ in true }
    }
}
