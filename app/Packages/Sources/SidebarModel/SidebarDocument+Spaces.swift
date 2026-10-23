import Foundation

extension SidebarDocument {
    public func space(_ id: SpaceID) -> Space? {
        spaces.first { $0.id == id }
    }

    /// Adds a space at the end with empty pinned and unpinned sections.
    @discardableResult
    public mutating func addSpace(title: String?, icon: String?, now: Date) -> SpaceID {
        let id = SpaceID.make()
        let pinned = SidebarItem(id: .make(), parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(.pinned(id)))
        let unpinned = SidebarItem(id: .make(), parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(.unpinned(id)))
        itemsByID[pinned.id] = pinned
        itemsByID[unpinned.id] = unpinned
        spaces.append(Space(id: id, title: title, icon: icon, theme: nil, pinnedContainerID: pinned.id, unpinnedContainerID: unpinned.id))
        return id
    }

    /// Removes a space, both of its sections and everything in them. Returns the removed items.
    @discardableResult
    public mutating func removeSpace(_ id: SpaceID) throws -> [SidebarItem] {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw SidebarError.spaceNotFound(id) }
        guard spaces.count > 1 else { throw SidebarError.cannotRemoveLastSpace }
        let space = spaces.remove(at: index)

        var removed: [SidebarItem] = []
        var queue = [space.pinnedContainerID, space.unpinnedContainerID]
        while !queue.isEmpty {
            guard let current = itemsByID.removeValue(forKey: queue.removeFirst()) else { continue }
            removed.append(current)
            queue.append(contentsOf: current.childIDs)
        }
        return removed
    }

    /// Moves a space to `index`, clamped to the valid range.
    public mutating func moveSpace(_ id: SpaceID, to index: Int) throws {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { throw SidebarError.spaceNotFound(id) }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: clamped(index, count: spaces.count))
    }

    public mutating func updateSpace(_ id: SpaceID, title: String?, icon: String?, theme: SpaceTheme?) throws {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw SidebarError.spaceNotFound(id) }
        spaces[index].title = title
        spaces[index].icon = icon
        spaces[index].theme = theme
    }
}
