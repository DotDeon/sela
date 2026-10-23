import Foundation

extension SidebarDocument {
    public static let maximumSplitPanes = 4

    /// Puts tab `id` right after tab `anchor` in a split. When `anchor` isn't in a split yet, a new side-by-side
    /// split takes its place. Pane sizes reset to equal. Returns the split's ID.
    @discardableResult
    public mutating func addToSplit(_ id: ItemID, with anchor: ItemID) throws -> ItemID {
        for candidate in [id, anchor] {
            guard case .tab = try requireItem(candidate).kind, containerRole(of: candidate) != .favorites, id != anchor else {
                throw SidebarError.notAllowedInSplit(candidate)
            }
        }
        let anchorItem = try requireItem(anchor)
        guard let parentID = anchorItem.parentID else { throw SidebarError.notAllowedInSplit(anchor) }

        if case .split = itemsByID[parentID]?.kind {
            let panes = itemsByID[parentID]!.childIDs
            guard panes.contains(id) || panes.count < Self.maximumSplitPanes else { throw SidebarError.splitFull(parentID) }
            if panes.contains(id) {
                // Reordering within the split, which mustn't collapse it on the way.
                itemsByID[parentID]!.childIDs.removeAll { $0 == id }
            } else {
                try detach(id)
            }
            let index = itemsByID[parentID]!.childIDs.firstIndex(of: anchor)! + 1
            itemsByID[parentID]!.childIDs.insert(id, at: index)
            itemsByID[id]!.parentID = parentID
            evenSplitSizes(parentID)
            return parentID
        }

        let splitID = ItemID.make()
        let split = SidebarItem(id: splitID, parentID: parentID, childIDs: [], title: nil, createdAt: anchorItem.createdAt, isUnread: false,
                                kind: .split(SplitInfo(orientation: .horizontal, fractions: [])))
        let anchorIndex = itemsByID[parentID]!.childIDs.firstIndex(of: anchor)!
        itemsByID[splitID] = split
        itemsByID[parentID]!.childIDs[anchorIndex] = splitID
        itemsByID[anchor]!.parentID = splitID
        try detach(id)
        itemsByID[splitID]!.childIDs = [anchor, id]
        itemsByID[id]!.parentID = splitID
        evenSplitSizes(splitID)
        return splitID
    }

    /// Replaces a split with its tabs, in order, where the split was.
    public mutating func separate(_ splitID: ItemID) throws {
        let split = try requireSplit(splitID)
        guard let parentID = split.parentID, let index = itemsByID[parentID]?.childIDs.firstIndex(of: splitID) else { return }
        itemsByID[parentID]!.childIDs.replaceSubrange(index...index, with: split.childIDs)
        for childID in split.childIDs { itemsByID[childID]!.parentID = parentID }
        itemsByID[splitID] = nil
    }

    /// Sets each pane's share. Throws unless there's one positive share per pane and they add up to 1.
    public mutating func setSplitFractions(_ splitID: ItemID, _ fractions: [Double]) throws {
        let split = try requireSplit(splitID)
        guard case .split(var info) = split.kind, fractions.count == split.childIDs.count,
              fractions.allSatisfy({ $0 > 0 }), abs(fractions.reduce(0, +) - 1) < 0.001
        else { throw SidebarError.integrity("\(fractions) doesn't fit split \(splitID)") }
        info.fractions = fractions
        itemsByID[splitID]!.kind = .split(info)
    }

    public mutating func setSplitOrientation(_ splitID: ItemID, _ orientation: SplitOrientation) throws {
        guard case .split(var info) = try requireSplit(splitID).kind else { return }
        info.orientation = orientation
        itemsByID[splitID]!.kind = .split(info)
    }

    /// The split a tab is a pane of, or nil.
    public func splitID(containing tabID: ItemID) -> ItemID? {
        guard let parentID = itemsByID[tabID]?.parentID, case .split = itemsByID[parentID]?.kind else { return nil }
        return parentID
    }

    // MARK: Helpers

    /// Only tabs outside favourites go in a split, and at most four of them.
    func checkSplitMembership(_ item: SidebarItem, in parent: SidebarItem) throws {
        guard case .split = parent.kind else { return }
        guard case .tab = item.kind, containerRole(of: item.id) != .favorites else { throw SidebarError.notAllowedInSplit(item.id) }
        guard parent.childIDs.count < Self.maximumSplitPanes else { throw SidebarError.splitFull(parent.id) }
    }

    /// After a pane leaves: one pane left takes the split's place, none left removes it, otherwise sizes even out.
    mutating func collapseSplitIfNeeded(_ splitID: ItemID) {
        guard let split = itemsByID[splitID], case .split = split.kind else { return }
        guard split.childIDs.count < 2 else {
            evenSplitSizes(splitID)
            return
        }
        guard let parentID = split.parentID, let index = itemsByID[parentID]?.childIDs.firstIndex(of: splitID) else { return }
        if let last = split.childIDs.first {
            itemsByID[parentID]!.childIDs[index] = last
            itemsByID[last]!.parentID = parentID
        } else {
            itemsByID[parentID]!.childIDs.remove(at: index)
        }
        itemsByID[splitID] = nil
    }

    mutating func evenSplitSizes(_ splitID: ItemID) {
        guard let split = itemsByID[splitID], case .split(var info) = split.kind else { return }
        info.fractions = SplitInfo.even(split.childIDs.count)
        itemsByID[splitID]!.kind = .split(info)
    }

    /// Takes an item out of its parent, collapsing the split it leaves when that's a split.
    private mutating func detach(_ id: ItemID) throws {
        guard let oldParentID = try requireItem(id).parentID else { return }
        itemsByID[oldParentID]?.childIDs.removeAll { $0 == id }
        itemsByID[id]!.parentID = nil
        collapseSplitIfNeeded(oldParentID)
    }

    private func requireSplit(_ id: ItemID) throws -> SidebarItem {
        let item = try requireItem(id)
        guard case .split = item.kind else { throw SidebarError.integrity("\(id) isn't a split") }
        return item
    }
}
