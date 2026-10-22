import Foundation
import SidebarModel

/// A plain-text summary of an import, for checking it against what Arc shows.
public func inspectReport(_ result: ArcImportResult) -> String {
    let document = result.document
    var lines = ["Spaces: \(document.spaces.count)"]

    for space in document.spaces {
        let pinned = counts(under: space.pinnedContainerID, in: document)
        let unpinned = counts(under: space.unpinnedContainerID, in: document)
        let folders = pinned.folders == 1 ? "1 folder" : "\(pinned.folders) folders"
        lines.append("  \(space.title ?? "Untitled space"): \(pinned.tabs) pinned (\(folders)), \(unpinned.tabs) unpinned")
    }

    lines.append("Favourites: \(counts(under: document.favoritesContainerID, in: document).tabs)")
    lines.append("Warnings: \(result.warnings.count)")
    lines.append(contentsOf: result.warnings.sorted { order($0) < order($1) }.map { "  " + describe($0) })
    return lines.joined(separator: "\n")
}

private func counts(under id: ItemID, in document: SidebarDocument) -> (tabs: Int, folders: Int) {
    var tabs = 0
    var folders = 0
    var queue = document.children(of: id)
    while !queue.isEmpty {
        let item = queue.removeFirst()
        switch item.kind {
        case .tab: tabs += 1
        case .folder: folders += 1
        case .container: break
        }
        queue.append(contentsOf: document.children(of: item.id))
    }
    return (tabs, folders)
}

private func order(_ warning: ArcImportWarning) -> Int {
    switch warning {
    case .unreadableItem: 0
    case .unsupportedItem: 1
    case .danglingChild: 2
    case .unreachableItems: 3
    case .missingFavorites: 4
    }
}

private func describe(_ warning: ArcImportWarning) -> String {
    switch warning {
    case .unreadableItem(let id):
        "Skipped unreadable item \(id)"
    case .unsupportedItem(let id, let kind):
        "Skipped unsupported item \(id) (\(kind))"
    case .danglingChild(let parent, let child):
        "Dropped missing child \(child) from \(parent)"
    case .unreachableItems(let count):
        count == 1 ? "Dropped 1 item not reachable from any space" : "Dropped \(count) items not reachable from any space"
    case .missingFavorites:
        "No favourites found, created an empty favourites section"
    }
}
