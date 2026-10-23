import Foundation
@testable import SidebarModel

let fixtureDate = Date(timeIntervalSince1970: 0)

func fixtureItem(_ id: ItemID, parent: ItemID?, children: [ItemID] = [], kind: SidebarItem.Kind) -> SidebarItem {
    SidebarItem(id: id, parentID: parent, childIDs: children, title: nil, createdAt: fixtureDate, isUnread: false, kind: kind)
}

func fixtureTab(_ id: ItemID, parent: ItemID) -> SidebarItem {
    fixtureItem(id, parent: parent, kind: .tab(TabInfo(savedURL: URL(string: "https://\(id).example.com/"), savedTitle: nil, lastActiveAt: nil, isMuted: false)))
}

/// Space "S": pinned "P" (folder "folder" (collapsed) > folder "sub" > tab "t3"; tab "t1"), unpinned "U" (tab "t2").
/// Favourites "F" (tab "f1").
func fixtureDocument() -> SidebarDocument {
    let items = [
        fixtureItem("F", parent: nil, children: ["f1"], kind: .container(.favorites)),
        fixtureTab("f1", parent: "F"),
        fixtureItem("P", parent: nil, children: ["folder", "t1"], kind: .container(.pinned("S"))),
        fixtureItem("U", parent: nil, children: ["t2"], kind: .container(.unpinned("S"))),
        fixtureItem("folder", parent: "P", children: ["sub"], kind: .folder(FolderInfo(icon: nil, isExpanded: false))),
        fixtureItem("sub", parent: "folder", children: ["t3"], kind: .folder(FolderInfo(icon: nil, isExpanded: true))),
        fixtureTab("t3", parent: "sub"),
        fixtureTab("t1", parent: "P"),
        fixtureTab("t2", parent: "U"),
    ]
    let space = Space(id: "S", title: "Space", icon: nil, theme: nil, pinnedContainerID: "P", unpinnedContainerID: "U")
    return SidebarDocument(version: SidebarDocument.currentVersion, spaces: [space], favoritesContainerID: "F", items: items)
}
