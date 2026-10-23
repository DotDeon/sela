import Foundation
import Testing
import Sidebar
import SidebarModel

@MainActor
private func makeStore(
    folder: URL? = nil,
    saveDelay: Duration = .milliseconds(20),
    firstRun: () -> SidebarDocument? = { fixtureDocument() }
) throws -> (SidebarStore, SidebarDocumentStore) {
    let folder = try folder ?? temporaryFolder()
    let fileStore = SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json"))
    let store = SidebarStore(fileStore: fileStore, saveDelay: saveDelay, now: { fixtureDate }, firstRunDocument: firstRun)
    return (store, fileStore)
}

@MainActor @Test func missingFileUsesFirstRunDocumentAndSavesIt() throws {
    let (store, fileStore) = try makeStore()
    #expect(store.document == fixtureDocument())
    #expect(try fileStore.load() == fixtureDocument())
    #expect(store.loadProblem == nil)
}

@MainActor @Test func missingFileWithoutFirstRunStartsEmpty() throws {
    let (store, _) = try makeStore(firstRun: { nil })
    #expect(store.document.spaces.count == 1)
}

@MainActor @Test func existingFileIsLoaded() throws {
    let folder = try temporaryFolder()
    _ = try makeStore(folder: folder)
    var called = false
    let (store, _) = try makeStore(folder: folder, firstRun: { called = true; return nil })
    #expect(!called)
    #expect(store.document == fixtureDocument())
}

@MainActor @Test func corruptFileStartsEmptyAndReportsBackup() throws {
    let folder = try temporaryFolder()
    try Data("{ not json".utf8).write(to: folder.appending(path: "Sidebar.json"))
    let (store, _) = try makeStore(folder: folder)
    guard case .corrupt(let backupURL) = store.loadProblem else {
        Issue.record("expected a corrupt-file problem, got \(String(describing: store.loadProblem))")
        return
    }
    #expect(FileManager.default.fileExists(atPath: backupURL.path))
    #expect(store.document.spaces.count == 1)
}

@MainActor @Test func newerVersionIsNeverOverwritten() throws {
    let folder = try temporaryFolder()
    let file = folder.appending(path: "Sidebar.json")
    let original = Data(#"{ "version": 2, "spaces": [], "items": [] }"#.utf8)
    try original.write(to: file)
    let (store, _) = try makeStore(folder: folder)
    #expect(store.loadProblem == .newerVersion(2))
    store.createTab(url: nil, title: nil, in: store.document.spaces[0].unpinnedContainerID, at: 0)
    store.saveNow()
    #expect(try Data(contentsOf: file) == original)
}

@MainActor @Test func editsAreSavedAfterTheDelay() async throws {
    let (store, fileStore) = try makeStore()
    let id = store.createTab(url: URL(string: "https://new.example.com/"), title: nil, in: "U", at: 0)
    try await eventually { (try? fileStore.load())??.item(id) != nil }
}

@MainActor @Test func saveNowWritesPendingChange() throws {
    let (store, fileStore) = try makeStore(saveDelay: .seconds(60))
    let id = store.createTab(url: nil, title: nil, in: "U", at: 0)
    #expect(try fileStore.load()?.item(id) == nil)
    store.saveNow()
    #expect(try fileStore.load()?.item(id) != nil)
}

@MainActor @Test func createTabAtTopOfUnpinned() throws {
    let (store, _) = try makeStore()
    let id = store.createTab(url: URL(string: "https://new.example.com/"), title: "New", in: "U", at: 0)
    #expect(store.document.item("U")?.childIDs == [id, "u1", "u2"])
    #expect(tabInfo(store.document, id)?.savedURL == URL(string: "https://new.example.com/"))
    #expect(tabInfo(store.document, id)?.savedTitle == "New")
    #expect(store.document.item(id)?.createdAt == fixtureDate)
}

@MainActor @Test func createFolderInPinned() throws {
    let (store, _) = try makeStore()
    let id = store.createFolder(title: "Work", in: "P", at: 0)
    #expect(store.document.item("P")?.childIDs.first == id)
    #expect(store.document.item(id)?.title == "Work")
}

@MainActor @Test func pinMovesToEndOfPinned() throws {
    let (store, _) = try makeStore()
    store.pin("u1", in: "S")
    #expect(store.document.item("P")?.childIDs == ["fold", "p1", "u1"])
}

@MainActor @Test func unpinMovesToTopOfUnpinned() throws {
    let (store, _) = try makeStore()
    store.unpin("p1", in: "S")
    #expect(store.document.item("U")?.childIDs == ["p1", "u1", "u2"])
}

@MainActor @Test func addToFavoritesAppends() throws {
    let (store, _) = try makeStore()
    store.addToFavorites("u2")
    #expect(store.document.item("F")?.childIDs == ["f1", "u2"])
}

@MainActor @Test func recordPageUpdatesUnpinnedTabs() throws {
    let (store, _) = try makeStore()
    store.recordPage("u1", url: URL(string: "https://elsewhere.example.com/"), title: "Elsewhere")
    #expect(tabInfo(store.document, "u1")?.savedURL == URL(string: "https://elsewhere.example.com/"))
    #expect(tabInfo(store.document, "u1")?.savedTitle == "Elsewhere")
}

@MainActor @Test func recordPageLeavesPinnedTabsAlone() throws {
    let (store, _) = try makeStore()
    store.recordPage("p1", url: URL(string: "https://elsewhere.example.com/"), title: "Elsewhere")
    store.recordPage("f1", url: URL(string: "https://elsewhere.example.com/"), title: "Elsewhere")
    #expect(tabInfo(store.document, "p1") == tabInfo(fixtureDocument(), "p1"))
    #expect(tabInfo(store.document, "f1") == tabInfo(fixtureDocument(), "f1"))
}

@MainActor @Test func markActiveSetsTime() throws {
    let (store, _) = try makeStore()
    store.markActive("p1", at: fixtureDate)
    #expect(tabInfo(store.document, "p1")?.lastActiveAt == fixtureDate)
}

@MainActor @Test func renameBlankClearsTitle() throws {
    let (store, _) = try makeStore()
    store.rename("p1", to: "Mail")
    #expect(store.document.item("p1")?.title == "Mail")
    store.rename("p1", to: "  ")
    #expect(store.document.item("p1")?.title == nil)
}

@MainActor @Test func setExpandedSavesFolderState() throws {
    let (store, _) = try makeStore()
    store.setExpanded("fold", false)
    #expect(store.document.item("fold")?.kind == .folder(FolderInfo(icon: nil, isExpanded: false)))
}

@MainActor @Test func clearUnpinnedRemovesOnlyThatSpace() throws {
    let (store, _) = try makeStore()
    store.createTab(url: nil, title: nil, in: "U2", at: 0)
    let removed = store.clearUnpinned(in: "S")
    #expect(removed == ["u1", "u2"])
    #expect(store.document.item("U")?.childIDs == [])
    #expect(store.document.item("U2")?.childIDs.count == 1)
}

@MainActor @Test func spaceEditing() throws {
    let (store, _) = try makeStore()
    let id = store.addSpace(title: "Three")
    #expect(store.document.spaces.map(\.id) == ["S", "S2", id])
    store.moveSpace(id, to: 0)
    #expect(store.document.spaces.first?.id == id)
    store.updateSpace(id, title: "3", icon: "star", theme: nil)
    #expect(store.document.space(id)?.icon == "star")
    try store.removeSpace(id)
    #expect(store.document.spaces.map(\.id) == ["S", "S2"])
}

@MainActor @Test func removeSpaceRefusesLastSpace() throws {
    let (store, _) = try makeStore(firstRun: { nil })
    #expect(throws: SidebarError.cannotRemoveLastSpace) {
        try store.removeSpace(store.document.spaces[0].id)
    }
}

@MainActor @Test func unknownIDsAreIgnored() throws {
    let (store, _) = try makeStore()
    store.remove("nope")
    store.rename("nope", to: "x")
    store.pin("nope", in: "S")
    #expect(store.document == fixtureDocument())
}
