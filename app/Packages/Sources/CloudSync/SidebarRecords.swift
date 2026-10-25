import Foundation
import SidebarModel

/// Turns the sidebar into records and back. Spaces, profiles, the favourites and every item in a pinned section
/// or favourites are records. Unpinned sections and what's in them stay on this Mac.
public enum SidebarRecords {
    /// The favourites container's name on the wire. Each Mac made its own container with its own ID, so the
    /// record uses this name instead and each Mac puts its own ID back when it reads it.
    public static let favoritesAlias: ItemID = "favorites"

    /// Every synced record's body, by key.
    public static func bodies(of document: SidebarDocument) -> [RecordKey: SyncRecord.Body] {
        var bodies: [RecordKey: SyncRecord.Body] = [:]
        for (order, profile) in document.profiles.enumerated() {
            bodies[.profile(profile.id)] = .profile(.init(name: profile.name, icon: profile.icon, color: profile.color, order: order))
        }
        for (order, space) in document.spaces.enumerated() {
            bodies[.space(space.id)] = .space(.init(title: space.title, icon: space.icon, theme: space.theme,
                                                    pinnedContainerID: space.pinnedContainerID, profileID: space.profileID, order: order))
            addItems(under: space.pinnedContainerID, in: document, to: &bodies)
        }
        addItems(under: document.favoritesContainerID, in: document, to: &bodies)
        return bodies
    }

    private static func addItems(under rootID: ItemID, in document: SidebarDocument, to bodies: inout [RecordKey: SyncRecord.Body]) {
        var queue = [rootID]
        while !queue.isEmpty {
            guard let item = document.item(queue.removeFirst()) else { continue }
            bodies[.item(alias(item.id, in: document))] = .item(body(of: item, in: document))
            queue.append(contentsOf: item.childIDs)
        }
    }

    /// The shared part of an item. What's last active, unread or open is this Mac's own business.
    static func body(of item: SidebarItem, in document: SidebarDocument) -> SyncRecord.ItemBody {
        var kind = item.kind
        switch kind {
        case .tab(var info):
            info.lastActiveAt = nil
            kind = .tab(info)
        case .folder(var info):
            info.isExpanded = true
            kind = .folder(info)
        case .split, .container:
            break
        }
        return .init(parentID: item.parentID.map { alias($0, in: document) }, childIDs: item.childIDs, title: item.title, createdAt: item.createdAt, kind: kind)
    }

    static func alias(_ id: ItemID, in document: SidebarDocument) -> ItemID {
        id == document.favoritesContainerID ? favoritesAlias : id
    }

    /// The number of tabs, folders and splits among the bodies. Containers don't count, since they're never lost.
    public static func itemCount(_ bodies: [RecordKey: SyncRecord.Body]) -> Int {
        bodies.values.reduce(0) { count, body in
            if case .item(let item) = body, !item.isContainer { return count + 1 }
            return count
        }
    }
}

extension SyncRecord.ItemBody {
    var isContainer: Bool {
        if case .container = kind { return true }
        return false
    }
}
