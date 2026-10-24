import Foundation

extension SidebarDocument {
    /// Adds a new item under `parentID`. A nil or out-of-range index appends.
    public mutating func insert(_ item: SidebarItem, into parentID: ItemID, at index: Int?) throws {
        guard itemsByID[item.id] == nil else { throw SidebarError.duplicateItem(item.id) }
        let parent = try requireItem(parentID)
        guard parent.canHaveChildren else { throw SidebarError.parentCannotHaveChildren(parentID) }
        try checkFavoritesHoldOnlyTabs(item, in: parent)
        try checkSplitMembership(item, in: parent)

        var item = item
        item.parentID = parentID
        itemsByID[item.id] = item
        itemsByID[parentID]!.childIDs.insert(item.id, at: clamped(index, count: parent.childIDs.count))
        evenSplitSizes(parentID)
    }

    /// Moves an existing item under `parentID`. Validates everything before changing anything.
    public mutating func move(_ id: ItemID, to parentID: ItemID, at index: Int?) throws {
        let item = try checkMove(id, to: parentID)

        if let oldParentID = item.parentID {
            itemsByID[oldParentID]?.childIDs.removeAll { $0 == id }
        }
        let siblings = itemsByID[parentID]!.childIDs
        itemsByID[parentID]!.childIDs.insert(id, at: clamped(index, count: siblings.count))
        itemsByID[id]!.parentID = parentID
        if let oldParentID = item.parentID, oldParentID != parentID {
            collapseSplitIfNeeded(oldParentID)
        }
        evenSplitSizes(parentID)
    }

    /// Removes an item and everything under it. Returns the removed items, root first.
    @discardableResult
    public mutating func remove(_ id: ItemID) throws -> [SidebarItem] {
        let item = try requireItem(id)
        guard !item.isContainer else { throw SidebarError.cannotMoveContainer(id) }

        var removed: [SidebarItem] = []
        var queue = [id]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard let current = itemsByID.removeValue(forKey: next) else { continue }
            removed.append(current)
            queue.append(contentsOf: current.childIDs)
        }
        if let parentID = item.parentID {
            itemsByID[parentID]?.childIDs.removeAll { $0 == id }
            collapseSplitIfNeeded(parentID)
        }
        return removed
    }

    /// Checks that the tree is consistent. Throws `SidebarError.integrity` describing the first problem.
    public func validate() throws {
        func fail(_ message: String) -> SidebarError { .integrity(message) }

        for item in itemsByID.values {
            for childID in item.childIDs {
                guard let child = itemsByID[childID] else { throw fail("\(item.id) lists missing child \(childID)") }
                guard child.parentID == item.id else { throw fail("\(childID) is listed under \(item.id) but its parent is \(child.parentID?.rawValue ?? "none")") }
            }
            if item.isContainer {
                guard item.parentID == nil else { throw fail("container \(item.id) has a parent") }
            } else {
                guard let parentID = item.parentID else { throw fail("\(item.id) has no parent") }
                guard let parent = itemsByID[parentID], parent.childIDs.contains(item.id) else {
                    throw fail("\(item.id) is not listed under its parent \(parentID)")
                }
                guard parent.canHaveChildren else { throw fail("\(parentID) cannot have children") }
            }
            if case .split(let info) = item.kind {
                guard (2...SidebarDocument.maximumSplitPanes).contains(item.childIDs.count) else { throw fail("split \(item.id) has \(item.childIDs.count) panes") }
                guard info.fractions.count == item.childIDs.count else { throw fail("split \(item.id) has \(info.fractions.count) sizes for \(item.childIDs.count) panes") }
                for childID in item.childIDs {
                    guard case .tab = itemsByID[childID]?.kind else { throw fail("split \(item.id) holds \(childID), which isn't a tab") }
                }
                guard item.parentID != favoritesContainerID else { throw fail("split \(item.id) is in favourites") }
            }
        }

        // Every non-container must reach a container without looping.
        for item in itemsByID.values where !item.isContainer {
            var seen: Set<ItemID> = [item.id]
            var current = item
            while let parentID = current.parentID {
                guard seen.insert(parentID).inserted else { throw fail("cycle at \(item.id)") }
                current = itemsByID[parentID]!
            }
        }

        guard !spaces.isEmpty else { throw fail("there are no spaces") }
        try requireContainer(favoritesContainerID, role: .favorites)
        for space in spaces {
            try requireContainer(space.pinnedContainerID, role: .pinned(space.id))
            try requireContainer(space.unpinnedContainerID, role: .unpinned(space.id))
        }
        try validateProfiles()
    }

    /// True when `move(_:to:at:)` would succeed.
    public func canMove(_ id: ItemID, to parentID: ItemID) -> Bool {
        (try? checkMove(id, to: parentID)) != nil
    }

    /// Sets an item's custom title. Nil clears it.
    public mutating func setTitle(_ id: ItemID, _ title: String?) throws {
        _ = try requireItem(id)
        itemsByID[id]!.title = title
    }

    public mutating func setExpanded(_ id: ItemID, _ isExpanded: Bool) throws {
        guard case .folder(var info) = try requireItem(id).kind else { throw SidebarError.notAFolder(id) }
        info.isExpanded = isExpanded
        itemsByID[id]!.kind = .folder(info)
    }

    public mutating func updateTab(_ id: ItemID, _ change: (inout TabInfo) -> Void) throws {
        guard case .tab(var info) = try requireItem(id).kind else { throw SidebarError.notATab(id) }
        change(&info)
        itemsByID[id]!.kind = .tab(info)
    }

    // MARK: Helpers

    /// The checks `move` makes, in order. Returns the item being moved.
    private func checkMove(_ id: ItemID, to parentID: ItemID) throws -> SidebarItem {
        let item = try requireItem(id)
        guard !item.isContainer else { throw SidebarError.cannotMoveContainer(id) }
        let parent = try requireItem(parentID)
        guard parent.canHaveChildren else { throw SidebarError.parentCannotHaveChildren(parentID) }
        guard parentID != id, !isDescendant(parentID, of: id) else { throw SidebarError.wouldCreateCycle(id) }
        try checkFavoritesHoldOnlyTabs(item, in: parent)
        if item.parentID != parentID {
            try checkSplitMembership(item, in: parent)
        }
        return item
    }

    /// Favourites are a grid of site icons, so they hold tabs only.
    private func checkFavoritesHoldOnlyTabs(_ item: SidebarItem, in parent: SidebarItem) throws {
        guard parent.kind == .container(.favorites) else { return }
        guard case .tab = item.kind else { throw SidebarError.notATab(item.id) }
    }

    func requireItem(_ id: ItemID) throws -> SidebarItem {
        guard let item = itemsByID[id] else { throw SidebarError.itemNotFound(id) }
        return item
    }

    private func requireContainer(_ id: ItemID, role: ContainerRole) throws {
        guard itemsByID[id]?.kind == .container(role) else {
            throw SidebarError.integrity("container \(id) is missing or not \(role)")
        }
    }

    private func isDescendant(_ candidate: ItemID, of ancestor: ItemID) -> Bool {
        var current = itemsByID[candidate]?.parentID
        var steps = 0
        while let id = current, steps <= itemsByID.count {
            if id == ancestor { return true }
            current = itemsByID[id]?.parentID
            steps += 1
        }
        return false
    }

    func clamped(_ index: Int?, count: Int) -> Int {
        guard let index else { return count }
        return min(max(index, 0), count)
    }
}
