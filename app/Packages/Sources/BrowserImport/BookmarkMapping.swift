import Foundation
import SidebarModel

/// How many tabs and folders an import added.
public struct BookmarkImportCount: Equatable, Sendable {
    public var tabs: Int
    public var folders: Int

    public init(tabs: Int = 0, folders: Int = 0) {
        self.tabs = tabs
        self.folders = folders
    }
}

extension SidebarDocument {
    /// Adds bookmarks to the end of a space's pinned section as pinned tabs and folders, keeping their order and
    /// nesting. Non-web addresses are skipped, and so are addresses already pinned in the space, in favourites or
    /// earlier in the import. A folder whose name matches one already at the same level is merged into it, so
    /// importing twice adds nothing. Folders left empty aren't added.
    @discardableResult
    public mutating func addPinnedBookmarks(_ bookmarks: [ImportedBookmark], in spaceID: SpaceID, now: Date) -> BookmarkImportCount {
        guard let pinned = space(spaceID)?.pinnedContainerID else { return BookmarkImportCount() }
        var seen = Set((tabIDs(under: pinned) + tabIDs(under: favoritesContainerID)).compactMap(savedAddress))
        var count = BookmarkImportCount()
        add(bookmarks, into: pinned, seen: &seen, count: &count, now: now)
        return count
    }

    private mutating func add(_ bookmarks: [ImportedBookmark], into parentID: ItemID, seen: inout Set<String>, count: inout BookmarkImportCount, now: Date) {
        for bookmark in bookmarks {
            switch bookmark {
            case .link(let title, let url):
                guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      seen.insert(url.absoluteString).inserted
                else { continue }
                let tab = SidebarItem(id: .make(), parentID: parentID, childIDs: [], title: nil, createdAt: now, isUnread: false,
                                      kind: .tab(TabInfo(savedURL: url, savedTitle: title, lastActiveAt: nil, isMuted: false)))
                guard (try? insert(tab, into: parentID, at: nil)) != nil else { continue }
                count.tabs += 1
            case .folder(let title, let children):
                let name = title.isEmpty ? nil : title
                if let existing = self.children(of: parentID).first(where: { $0.title == name && $0.isFolder }) {
                    add(children, into: existing.id, seen: &seen, count: &count, now: now)
                    continue
                }
                let folder = SidebarItem(id: .make(), parentID: parentID, childIDs: [], title: name, createdAt: now, isUnread: false,
                                         kind: .folder(FolderInfo(icon: nil, isExpanded: false)))
                guard (try? insert(folder, into: parentID, at: nil)) != nil else { continue }
                let before = count
                add(children, into: folder.id, seen: &seen, count: &count, now: now)
                if count == before {
                    _ = try? remove(folder.id)
                } else {
                    count.folders += 1
                }
            }
        }
    }

    private func savedAddress(_ id: ItemID) -> String? {
        if case .tab(let info) = item(id)?.kind { return info.savedURL?.absoluteString }
        return nil
    }
}

private extension SidebarItem {
    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
}
