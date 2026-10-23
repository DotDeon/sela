import Foundation
import Testing
import SidebarModel

let fixtureDate = Date(timeIntervalSince1970: 1_800_000_000)

func fixtureItem(_ id: ItemID, parent: ItemID?, children: [ItemID] = [], kind: SidebarItem.Kind) -> SidebarItem {
    SidebarItem(id: id, parentID: parent, childIDs: children, title: nil, createdAt: fixtureDate, isUnread: false, kind: kind)
}

func fixtureTab(_ id: ItemID, parent: ItemID) -> SidebarItem {
    fixtureItem(id, parent: parent, kind: .tab(TabInfo(savedURL: URL(string: "https://\(id).example.com/"), savedTitle: "\(id) title", lastActiveAt: nil, isMuted: false)))
}

/// Space "S": pinned "P" (folder "fold" (expanded) > tab "p2"; tab "p1"), unpinned "U" (tabs "u1", "u2").
/// Space "S2": pinned "P2" (tab "q1"), unpinned "U2" (empty). Favourites "F" (tab "f1").
func fixtureDocument() -> SidebarDocument {
    let items = [
        fixtureItem("F", parent: nil, children: ["f1"], kind: .container(.favorites)),
        fixtureTab("f1", parent: "F"),
        fixtureItem("P", parent: nil, children: ["fold", "p1"], kind: .container(.pinned("S"))),
        fixtureItem("fold", parent: "P", children: ["p2"], kind: .folder(FolderInfo(icon: nil, isExpanded: true))),
        fixtureTab("p2", parent: "fold"),
        fixtureTab("p1", parent: "P"),
        fixtureItem("U", parent: nil, children: ["u1", "u2"], kind: .container(.unpinned("S"))),
        fixtureTab("u1", parent: "U"),
        fixtureTab("u2", parent: "U"),
        fixtureItem("P2", parent: nil, children: ["q1"], kind: .container(.pinned("S2"))),
        fixtureTab("q1", parent: "P2"),
        fixtureItem("U2", parent: nil, kind: .container(.unpinned("S2"))),
    ]
    let spaces = [
        Space(id: "S", title: "One", icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "U"),
        Space(id: "S2", title: "Two", icon: nil, theme: nil, pinnedContainerID: "P2", unpinnedContainerID: "U2"),
    ]
    return SidebarDocument(version: SidebarDocument.currentVersion, spaces: spaces, favoritesContainerID: "F", items: items)
}

func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "brow-sidebar-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func tabInfo(_ document: SidebarDocument, _ id: ItemID) -> TabInfo? {
    if case .tab(let info) = document.item(id)?.kind { return info }
    return nil
}

/// Polls every 10 ms for up to 2 seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
