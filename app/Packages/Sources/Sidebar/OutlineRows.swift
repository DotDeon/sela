import Foundation
import SidebarModel

/// A row in a space's outline: a tab or folder, or the divider between pinned and unpinned tabs.
public enum OutlineRow: Hashable, Sendable {
    case item(ItemID)
    case divider
}

/// Pinned tabs and folders, the divider, then unpinned tabs.
public func rootRows(for space: Space, in document: SidebarDocument) -> [OutlineRow] {
    childRows(of: space.pinnedContainerID, in: document) + [.divider] + childRows(of: space.unpinnedContainerID, in: document)
}

/// A split's tabs show inside its one row, so a split has no child rows.
public func childRows(of id: ItemID, in document: SidebarDocument) -> [OutlineRow] {
    guard let item = document.item(id) else { return [] }
    if case .split = item.kind { return [] }
    return item.childIDs.map(OutlineRow.item)
}

/// Each visible parent's rows, keyed by parent. Nil is the root. Collapsed folders are left out.
public typealias OutlineSnapshot = [OutlineRow?: [OutlineRow]]

public func outlineSnapshot(for space: Space, in document: SidebarDocument) -> OutlineSnapshot {
    var snapshot: OutlineSnapshot = [nil: rootRows(for: space, in: document)]
    var queue = snapshot[nil]!
    while !queue.isEmpty {
        guard case .item(let id) = queue.removeFirst(),
              case .folder(let info) = document.item(id)?.kind, info.isExpanded
        else { continue }
        let children = childRows(of: id, in: document)
        snapshot[.item(id)] = children
        queue.append(contentsOf: children)
    }
    return snapshot
}

/// Where a drop on the outline lands in the sidebar. Nil when the drop isn't allowed there.
/// `childIndex` -1 means "onto `parent`", as `NSOutlineView` reports it.
public func dropDestination(parent: OutlineRow?, childIndex: Int, space: Space, document: SidebarDocument) -> (parent: ItemID, index: Int?)? {
    switch parent {
    case nil:
        guard childIndex >= 0 else { return nil }
        let pinnedCount = document.item(space.pinnedContainerID)?.childIDs.count ?? 0
        if childIndex <= pinnedCount {
            return (space.pinnedContainerID, childIndex)
        }
        return (space.unpinnedContainerID, childIndex - pinnedCount - 1)
    case .item(let id):
        guard case .folder = document.item(id)?.kind else { return nil }
        return (id, childIndex >= 0 ? childIndex : nil)
    case .divider:
        return nil
    }
}
