import Foundation
import Testing
import BrowserImport
import SidebarModel

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func link(_ title: String?, _ address: String) -> ImportedBookmark {
    .link(title: title, url: URL(string: address)!)
}

/// The pinned section as nested titles: a tab's saved title, or a folder's name followed by its children.
private indirect enum Shape: Equatable {
    case tab(String?)
    case folder(String?, [Shape])
}

private func shape(of id: ItemID, in document: SidebarDocument) -> [Shape] {
    document.children(of: id).map { item in
        switch item.kind {
        case .tab(let info): .tab(info.savedTitle)
        default: .folder(item.title, shape(of: item.id, in: document))
        }
    }
}

private let sample: [ImportedBookmark] = [
    link("Example", "https://example.com/"),
    .folder(title: "Work", children: [
        link("Docs", "https://docs.example.com/"),
        .folder(title: "Nested", children: [link("Deep", "https://deep.example.com/")]),
    ]),
    link("Settings", "chrome://settings/"),
    link("Example again", "https://example.com/"),
    .folder(title: "Only junk", children: [link("Script", "javascript:void(0)")]),
]

@Test func bookmarksBecomePinnedTabsAndFoldersInOrder() throws {
    var document = SidebarDocument.empty(now: now)
    let space = document.spaces[0]
    let count = document.addPinnedBookmarks(sample, in: space.id, now: now)

    #expect(count == BookmarkImportCount(tabs: 3, folders: 2))
    #expect(shape(of: space.pinnedContainerID, in: document) == [
        .tab("Example"),
        .folder("Work", [.tab("Docs"), .folder("Nested", [.tab("Deep")])]),
    ])
    #expect(document.children(of: document.favoritesContainerID).isEmpty)
    #expect(document.children(of: space.unpinnedContainerID).isEmpty)
    try document.validate()

    let tab = try #require(document.children(of: space.pinnedContainerID).first)
    #expect(tab.title == nil)
    #expect(tab.kind == .tab(TabInfo(savedURL: URL(string: "https://example.com/"), savedTitle: "Example", lastActiveAt: nil, isMuted: false)))
}

@Test func bookmarksGoAfterWhatsAlreadyPinned() throws {
    var document = SidebarDocument.empty(now: now)
    let space = document.spaces[0]
    let existing = SidebarItem(id: "mine", parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false,
                               kind: .tab(TabInfo(savedURL: URL(string: "https://mine.example.com/"), savedTitle: "Mine", lastActiveAt: nil, isMuted: false)))
    try document.insert(existing, into: space.pinnedContainerID, at: nil)

    document.addPinnedBookmarks([link("New", "https://new.example.com/")], in: space.id, now: now)
    #expect(shape(of: space.pinnedContainerID, in: document) == [.tab("Mine"), .tab("New")])
}

@Test func importingTwiceAddsNothing() throws {
    var document = SidebarDocument.empty(now: now)
    let space = document.spaces[0]
    document.addPinnedBookmarks(sample, in: space.id, now: now)
    let once = document

    #expect(document.addPinnedBookmarks(sample, in: space.id, now: now) == BookmarkImportCount())
    #expect(document == once)
}

@Test func newBookmarksJoinAMatchingFolder() throws {
    var document = SidebarDocument.empty(now: now)
    let space = document.spaces[0]
    document.addPinnedBookmarks(sample, in: space.id, now: now)

    let count = document.addPinnedBookmarks([.folder(title: "Work", children: [link("Wiki", "https://wiki.example.com/")])], in: space.id, now: now)
    #expect(count == BookmarkImportCount(tabs: 1, folders: 0))
    #expect(shape(of: space.pinnedContainerID, in: document)[1] == .folder("Work", [.tab("Docs"), .folder("Nested", [.tab("Deep")]), .tab("Wiki")]))
}

@Test func favouritesCountAsAlreadyThere() throws {
    var document = SidebarDocument.empty(now: now)
    let favourite = SidebarItem(id: "fav", parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false,
                                kind: .tab(TabInfo(savedURL: URL(string: "https://example.com/"), savedTitle: nil, lastActiveAt: nil, isMuted: false)))
    try document.insert(favourite, into: document.favoritesContainerID, at: nil)

    #expect(document.addPinnedBookmarks([link("Example", "https://example.com/")], in: document.spaces[0].id, now: now) == BookmarkImportCount())
}

@Test func importsIntoTheChosenSpace() throws {
    var document = SidebarDocument.empty(now: now)
    let second = document.addSpace(title: "Second", icon: nil, now: now)
    document.addPinnedBookmarks([link("Example", "https://example.com/")], in: second, now: now)

    #expect(document.children(of: document.spaces[0].pinnedContainerID).isEmpty)
    #expect(shape(of: document.space(second)!.pinnedContainerID, in: document) == [.tab("Example")])
}
