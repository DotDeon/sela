import Foundation

extension SidebarDocument {
    /// The section an item lives in, found by walking up to its container. A container returns its own role.
    public func containerRole(of id: ItemID) -> ContainerRole? {
        var current = itemsByID[id]
        var steps = 0
        while let item = current, steps <= itemsByID.count {
            if case .container(let role) = item.kind { return role }
            current = item.parentID.flatMap { itemsByID[$0] }
            steps += 1
        }
        return nil
    }

    /// The space an item belongs to. Nil for favourites, which every space shares.
    public func spaceID(containing id: ItemID) -> SpaceID? {
        switch containerRole(of: id) {
        case .pinned(let space), .unpinned(let space): space
        case .favorites, nil: nil
        }
    }

    /// Every tab at or under `id`, depth-first, including tabs in collapsed folders.
    public func tabIDs(under id: ItemID) -> [ItemID] {
        guard let item = itemsByID[id] else { return [] }
        if case .tab = item.kind { return [id] }
        return item.childIDs.flatMap { tabIDs(under: $0) }
    }

    /// The folders an item sits in, outermost first. Empty for an item at the top of its section.
    public func folderIDs(containing id: ItemID) -> [ItemID] {
        var folders: [ItemID] = []
        var current = itemsByID[id]?.parentID.flatMap { itemsByID[$0] }
        var steps = 0
        while let item = current, steps <= itemsByID.count {
            if case .folder = item.kind { folders.insert(item.id, at: 0) }
            current = item.parentID.flatMap { itemsByID[$0] }
            steps += 1
        }
        return folders
    }

    /// The names of the folders an item sits in, outermost first. Untitled folders read "Folder".
    public func folderPath(of id: ItemID) -> [String] {
        folderIDs(containing: id).map { folder in
            guard let title = itemsByID[folder]?.title, !title.isEmpty else { return "Folder" }
            return title
        }
    }
}
