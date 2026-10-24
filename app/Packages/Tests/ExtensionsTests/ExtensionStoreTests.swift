import BrowserEngine
import Extensions
import Foundation
import Testing

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "sela-extensions-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Test func noFileMeansNoExtensions() throws {
    #expect(try ExtensionStore(folder: temporaryFolder()).load() == [])
}

@Test func recordsSurviveSavingAndLoading() throws {
    let store = ExtensionStore(folder: temporaryFolder())
    let permissions = ExtensionPermissions(granted: ["storage": .distantFuture], deniedMatchPatterns: ["*://bank.example/*": .distantFuture])
    let record = ExtensionRecord(id: "abc", name: "Dark Reader", version: "4.9", isEnabled: false,
                                 installedAt: Date(timeIntervalSince1970: 1_800_000_000), permissions: permissions)
    try store.save([record])
    #expect(try store.load() == [record])
}

@Test func newerFilesAreLeftAlone() throws {
    let store = ExtensionStore(folder: temporaryFolder())
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    try Data(#"{"version": 99, "extensions": []}"#.utf8).write(to: store.fileURL)
    #expect(throws: ExtensionStore.LoadError.newerVersion) { try store.load() }
}

@Test func brokenFilesAreReported() throws {
    let store = ExtensionStore(folder: temporaryFolder())
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: store.fileURL)
    #expect {
        try store.load()
    } throws: { error in
        if case .unreadable = error as? ExtensionStore.LoadError { return true }
        return false
    }
}

@Test func eachExtensionHasItsOwnFolder() {
    let store = ExtensionStore(folder: URL(fileURLWithPath: "/tmp/Extensions", isDirectory: true))
    #expect(store.contentFolder(for: "abc").path == "/tmp/Extensions/abc")
}
