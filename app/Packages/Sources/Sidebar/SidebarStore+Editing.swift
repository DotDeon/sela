import Foundation
import SidebarModel

/// Every edit the UI makes. Edits naming an unknown item or space do nothing,
/// because another window may have removed it a moment earlier.
extension SidebarStore {
    @discardableResult
    public func createTab(url: URL?, title: String?, in parentID: ItemID, at index: Int?) -> ItemID {
        let id = ItemID.make()
        let info = TabInfo(savedURL: url, savedTitle: title, lastActiveAt: nil, isMuted: false)
        let item = SidebarItem(id: id, parentID: parentID, childIDs: [], title: nil, createdAt: now(), isUnread: false, kind: .tab(info))
        try? change { try $0.insert(item, into: parentID, at: index) }
        return id
    }

    @discardableResult
    public func createFolder(title: String?, in parentID: ItemID, at index: Int?) -> ItemID {
        let id = ItemID.make()
        let item = SidebarItem(id: id, parentID: parentID, childIDs: [], title: title, createdAt: now(), isUnread: false, kind: .folder(FolderInfo(icon: nil, isExpanded: true)))
        try? change { try $0.insert(item, into: parentID, at: index) }
        return id
    }

    public func move(_ id: ItemID, to parentID: ItemID, at index: Int?) throws {
        try change { try $0.move(id, to: parentID, at: index) }
    }

    /// Removes a tab or folder and everything in it.
    public func remove(_ id: ItemID) {
        _ = try? change { try $0.remove(id) }
    }

    /// Puts tab `id` in a split right after `anchor`, making the split if needed. Nil when that isn't allowed.
    @discardableResult
    public func addToSplit(_ id: ItemID, with anchor: ItemID) -> ItemID? {
        var splitID: ItemID?
        try? change { splitID = try $0.addToSplit(id, with: anchor) }
        return splitID
    }

    /// Replaces a split with its tabs.
    public func separateSplit(_ id: ItemID) {
        try? change { try $0.separate(id) }
    }

    public func setSplitFractions(_ id: ItemID, _ fractions: [Double]) {
        try? change { try $0.setSplitFractions(id, fractions) }
    }

    public func setSplitOrientation(_ id: ItemID, _ orientation: SplitOrientation) {
        try? change { try $0.setSplitOrientation(id, orientation) }
    }

    /// Sets a custom title. Blank text clears it, so the page's own title shows.
    public func rename(_ id: ItemID, to title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? change { try $0.setTitle(id, trimmed?.isEmpty == false ? trimmed : nil) }
    }

    public func setExpanded(_ id: ItemID, _ isExpanded: Bool) {
        try? change { try $0.setExpanded(id, isExpanded) }
    }

    /// Moves an item to the end of the space's pinned section.
    public func pin(_ id: ItemID, in space: SpaceID) {
        guard let container = document.space(space)?.pinnedContainerID else { return }
        try? move(id, to: container, at: nil)
    }

    /// Moves an item to the top of the space's unpinned section.
    public func unpin(_ id: ItemID, in space: SpaceID) {
        guard let container = document.space(space)?.unpinnedContainerID else { return }
        try? move(id, to: container, at: 0)
    }

    public func addToFavorites(_ id: ItemID) {
        try? move(id, to: document.favoritesContainerID, at: nil)
    }

    /// Records where an unpinned tab is now, so it reopens there. Pinned tabs and favourites keep their saved address.
    public func recordPage(_ id: ItemID, url: URL?, title: String?) {
        // Pinned tabs and favourites keep their saved address, except one that was made blank and has none yet.
        let isUnpinned: Bool
        if case .unpinned = document.containerRole(of: id) { isUnpinned = true } else { isUnpinned = false }
        guard let info = tabInfo(id), isUnpinned || (info.savedURL == nil && url != nil) else { return }
        try? change {
            try $0.updateTab(id) { info in
                info.savedURL = url
                info.savedTitle = title
            }
        }
    }

    public func markActive(_ id: ItemID, at date: Date) {
        try? change { try $0.updateTab(id) { $0.lastActiveAt = date } }
    }

    /// Removes every unpinned tab in a space. Returns what was removed.
    @discardableResult
    public func clearUnpinned(in space: SpaceID) -> [ItemID] {
        guard let container = document.space(space)?.unpinnedContainerID else { return [] }
        let ids = document.item(container)?.childIDs ?? []
        change { document in
            for id in ids { _ = try? document.remove(id) }
        }
        return ids
    }

    @discardableResult
    public func addSpace(title: String?) -> SpaceID {
        let date = now()
        return change { $0.addSpace(title: title, icon: nil, now: date) }
    }

    public func removeSpace(_ id: SpaceID) throws {
        try change { _ = try $0.removeSpace(id) }
    }

    public func moveSpace(_ id: SpaceID, to index: Int) {
        try? change { try $0.moveSpace(id, to: index) }
    }

    public func updateSpace(_ id: SpaceID, title: String?, icon: String?, theme: SpaceTheme?) {
        try? change { try $0.updateSpace(id, title: title, icon: icon, theme: theme) }
    }
}

extension SidebarStore {
    fileprivate func tabInfo(_ id: ItemID) -> TabInfo? {
        if case .tab(let info) = document.item(id)?.kind { return info }
        return nil
    }
}
