import Foundation
import Sidebar
import SidebarModel

/// Unpinned tabs in every space that haven't been selected for `interval`. Inactivity counts from
/// `lastActiveAt`, or from `createdAt` for a tab that was never selected, but never from before `notBefore`:
/// the moment Brow started archiving, so tabs imported from Arc or kept from before get a full interval first.
/// Protected tabs are skipped.
public func inactiveTabs(in document: SidebarDocument, now: Date, after interval: TimeInterval, protecting: Set<ItemID>, notBefore: Date? = nil) -> [ItemID] {
    let cutoff = now.addingTimeInterval(-interval)
    if let notBefore, notBefore >= cutoff { return [] }
    func isDue(_ id: ItemID) -> Bool {
        guard !protecting.contains(id), let item = document.item(id), case .tab(let info) = item.kind else { return false }
        return (info.lastActiveAt ?? item.createdAt) < cutoff
    }
    // A split goes as a unit, once every one of its panes is due, wherever it sits.
    func due(under id: ItemID) -> [ItemID] {
        guard let item = document.item(id) else { return [] }
        switch item.kind {
        case .tab: return isDue(id) ? [id] : []
        case .split:
            let panes = document.tabIDs(under: id)
            return panes.allSatisfy(isDue) ? panes : []
        case .folder, .container: return item.childIDs.flatMap(due(under:))
        }
    }
    return document.spaces.flatMap { due(under: $0.unpinnedContainerID) }
}

/// An archive entry describing a sidebar tab as it's saved.
@MainActor
public func archiveEntry(for id: ItemID, in document: SidebarDocument, at date: Date, reason: ArchiveEntry.Reason = .closed) -> ArchiveEntry? {
    guard let item = document.item(id), case .tab(let info) = item.kind else { return nil }
    return ArchiveEntry(id: UUID(), url: info.savedURL, title: item.title ?? info.savedTitle, spaceID: document.spaceID(containing: id), archivedAt: date, reason: reason)
}

/// Moves every inactive unpinned tab from the sidebar into the archive. Returns the tabs moved.
@MainActor
@discardableResult
public func archiveInactiveTabs(sidebar: SidebarStore, archive: ArchiveStore, now: Date, after interval: TimeInterval, protecting: Set<ItemID>, notBefore: Date? = nil) -> [ItemID] {
    let due = inactiveTabs(in: sidebar.document, now: now, after: interval, protecting: protecting, notBefore: notBefore)
    archive.add(due.compactMap { archiveEntry(for: $0, in: sidebar.document, at: now, reason: .inactive) })
    for id in due { sidebar.remove(id) }
    return due
}
