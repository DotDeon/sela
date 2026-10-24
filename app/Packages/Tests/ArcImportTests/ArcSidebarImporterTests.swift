import Foundation
import Testing
import ArcImport
import SidebarModel

func fixtureURL() throws -> URL {
    try #require(Bundle.module.url(forResource: "StorableSidebar", withExtension: "json", subdirectory: "Fixtures"))
}

func importFixture() throws -> ArcImportResult {
    try ArcSidebarImporter().importSidebar(from: fixtureURL())
}

private func writeTemp(_ json: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "sela-arc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: "StorableSidebar.json")
    try Data(json.utf8).write(to: url)
    return url
}

private func tabInfo(_ doc: SidebarDocument, _ id: ItemID) throws -> TabInfo {
    guard case .tab(let info) = doc.item(id)?.kind else {
        Issue.record("\(id) is not a tab")
        throw CancellationError()
    }
    return info
}

@Test func importsSpacesInOrder() throws {
    let result = try importFixture()
    #expect(result.document.spaces.map(\.id) == ["space-A", "space-B"])
    #expect(result.document.spaces[0].title == "Work")
    #expect(result.document.spaces[0].icon == "💼")
    #expect(result.document.spaces[1].title == nil)
    #expect(result.document.spaces[0].pinnedContainerID == "A-pinned")
    #expect(result.document.spaces[0].unpinnedContainerID == "A-unpinned")
}

@Test func importsFavorites() throws {
    let doc = try importFixture().document
    #expect(doc.favoritesContainerID == "fav-root")
    #expect(doc.children(of: "fav-root").map(\.id) == ["fav-1"])
    let info = try tabInfo(doc, "fav-1")
    #expect(info.savedURL == URL(string: "https://mail.example.com/"))
    #expect(info.lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_000_000))
    #expect(info.isMuted == false)
}

@Test func importsPinnedFoldersAndTabs() throws {
    let doc = try importFixture().document
    #expect(doc.children(of: "A-pinned").map(\.id) == ["folder-1", "tab-p2"])
    #expect(doc.item("folder-1")?.kind == .folder(FolderInfo(icon: "📁", isExpanded: true)))
    #expect(doc.item("folder-1")?.title == "Projects")
    #expect(doc.children(of: "folder-1").map(\.id) == ["tab-p1"])
    #expect(doc.item("tab-p1")?.isUnread == true)
    #expect(doc.item("tab-p2")?.title == "My calendar")
    #expect(try tabInfo(doc, "tab-p2").isMuted == true)
}

@Test func importsUnpinnedTabs() throws {
    let doc = try importFixture().document
    #expect(doc.children(of: "A-unpinned").map(\.id) == ["tab-u1"])
    #expect(try tabInfo(doc, "tab-u1").lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_100_000))
}

@Test func reportsWarnings() throws {
    let warnings = try importFixture().warnings
    #expect(warnings.contains(.danglingChild(parent: "folder-1", child: "missing-id")))
    #expect(warnings.contains(.unsupportedItem(id: "easel-1", kind: "easel")))
    #expect(warnings.contains(.unreachableItems(count: 1)))
    #expect(warnings.count == 3)
}

@Test func resultValidates() throws {
    try importFixture().document.validate()
}

@Test func missingFileThrows() {
    let url = URL(fileURLWithPath: "/nonexistent/StorableSidebar.json")
    #expect(throws: ArcImportError.fileNotFound(url)) {
        try ArcSidebarImporter().importSidebar(from: url)
    }
}

@Test func oddLengthItemsArrayIsMalformed() throws {
    let url = try writeTemp(#"""
    { "version": 1, "sidebar": { "containers": [ { "global": {} },
      { "topAppsContainerIDs": [], "spaces": [], "items": [ "only-key" ] } ] } }
    """#)
    #expect {
        try ArcSidebarImporter().importSidebar(from: url)
    } throws: { error in
        if case ArcImportError.malformed = error { return true }
        return false
    }
}

@Test func fileWithoutSpacesThrows() throws {
    let url = try writeTemp(#"{ "version": 1, "sidebar": { "containers": [ { "global": {} } ] } }"#)
    #expect(throws: ArcImportError.noSpaces) {
        try ArcSidebarImporter().importSidebar(from: url)
    }
}

@Test func missingFavoritesCreatesEmptyContainer() throws {
    let url = try writeTemp(#"""
    { "version": 1, "sidebar": { "containers": [ { "global": {} }, {
      "spaces": [ "s", { "id": "s", "containerIDs": [ "pinned", "p", "unpinned", "u" ] } ],
      "items": [
        "p", { "id": "p", "parentID": null, "childrenIds": [], "createdAt": 1.0, "isUnread": false,
               "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "s" } } } } },
        "u", { "id": "u", "parentID": null, "childrenIds": [], "createdAt": 1.0, "isUnread": false,
               "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "s" } } } } }
      ] } ] } }
    """#)
    let result = try ArcSidebarImporter().importSidebar(from: url)
    #expect(result.warnings.contains(.missingFavorites))
    let favorites = try #require(result.document.item(result.document.favoritesContainerID))
    #expect(favorites.kind == .container(.favorites))
    #expect(favorites.childIDs.isEmpty)
    try result.document.validate()
}

@Test func unreadableItemIsSkippedWithWarning() throws {
    let url = try writeTemp(#"""
    { "version": 1, "sidebar": { "containers": [ { "global": {} }, {
      "topAppsContainerIDs": [ { "default": true }, "f" ],
      "spaces": [ "s", { "id": "s", "containerIDs": [ "pinned", "p", "unpinned", "u" ] } ],
      "items": [
        "f", { "id": "f", "parentID": null, "childrenIds": [], "createdAt": 1.0, "isUnread": false,
               "data": { "itemContainer": { "containerType": { "topApps": { "_0": { "default": true } } } } } },
        "p", { "id": "p", "parentID": null, "childrenIds": [ "bad", "good" ], "createdAt": 1.0, "isUnread": false,
               "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "s" } } } } },
        "bad", { "id": "bad", "parentID": "p", "childrenIds": [], "createdAt": "yesterday", "isUnread": false,
                 "data": { "tab": { "savedURL": "https://bad.example.com/" } } },
        "good", { "id": "good", "parentID": "p", "childrenIds": [], "createdAt": 2.0, "isUnread": false,
                  "data": { "tab": { "savedURL": "https://good.example.com/" } } },
        "u", { "id": "u", "parentID": null, "childrenIds": [], "createdAt": 1.0, "isUnread": false,
               "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "s" } } } } }
      ] } ] } }
    """#)
    let result = try ArcSidebarImporter().importSidebar(from: url)
    #expect(result.document.children(of: "p").map(\.id) == ["good"])
    #expect(result.warnings == [.unreadableItem(id: "bad")])
}
