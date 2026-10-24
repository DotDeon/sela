import Foundation
import SidebarModel

public struct ArcImportResult: Sendable {
    public var document: SidebarDocument
    public var warnings: [ArcImportWarning]
}

public enum ArcImportWarning: Equatable, Sendable {
    case unsupportedItem(id: ItemID, kind: String)
    case danglingChild(parent: ItemID, child: ItemID)
    case unreachableItems(count: Int)
    case missingFavorites
    case unreadableItem(id: ItemID)
}

public enum ArcImportError: Error, Equatable, Sendable {
    case fileNotFound(URL)
    case malformed(String)
    case noSpaces
}

/// Turns Arc's StorableSidebar.json into a Sela sidebar. Reads the file and never writes to it.
public struct ArcSidebarImporter: Sendable {
    public init() {}

    public func importSidebar(from fileURL: URL) throws -> ArcImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ArcImportError.fileNotFound(fileURL)
        }

        let file: ArcStorableSidebar
        do {
            file = try JSONDecoder().decode(ArcStorableSidebar.self, from: Data(contentsOf: fileURL))
        } catch is OddLengthPairsError {
            throw ArcImportError.malformed("a key/value array has an odd number of entries")
        } catch {
            throw ArcImportError.malformed(String(describing: error))
        }

        guard let container = file.sidebar.containers.first(where: { $0.spaces != nil }),
              let arcSpaces = container.spaces?.values, !arcSpaces.isEmpty
        else { throw ArcImportError.noSpaces }

        var builder = Builder(pairs: container.items?.pairs ?? [])

        let favoritesID: ItemID
        if let arcFavoritesID = container.topAppsContainerIDs?.pairs.first(where: { $0.key.isDefault })?.value {
            favoritesID = builder.addRoot(arcFavoritesID, role: .favorites)
        } else {
            favoritesID = builder.addRoot(nil, role: .favorites)
            builder.warnings.append(.missingFavorites)
        }

        let spaces = arcSpaces.map { arcSpace -> Space in
            let spaceID = SpaceID(rawValue: arcSpace.id)
            let pinned = builder.addRoot(arcSpace.containerID(labelled: "pinned"), role: .pinned(spaceID))
            let unpinned = builder.addRoot(arcSpace.containerID(labelled: "unpinned"), role: .unpinned(spaceID))
            return Space(
                id: spaceID,
                title: arcSpace.title,
                icon: arcSpace.customInfo?.iconType?.icon,
                theme: nil,
                pinnedContainerID: pinned,
                unpinnedContainerID: unpinned
            )
        }

        let unreachable = builder.arcItemsByID.count - builder.visited.count
        if unreachable > 0 {
            builder.warnings.append(.unreachableItems(count: unreachable))
        }

        let document = SidebarDocument(
            version: SidebarDocument.currentVersion,
            spaces: spaces,
            favoritesContainerID: favoritesID,
            items: builder.items
        )
        do {
            try document.validate()
        } catch {
            throw ArcImportError.malformed("imported sidebar is inconsistent: \(error)")
        }
        return ArcImportResult(document: document, warnings: builder.warnings)
    }
}

/// Walks Arc's items from each root container and builds Sela items.
private struct Builder {
    let arcItemsByID: [String: ArcItem]
    var visited: Set<String> = []
    var items: [SidebarItem] = []
    let unreadableIDs: Set<String>
    var warnings: [ArcImportWarning] = []

    init(pairs: [(key: String, value: LossyArcItem)]) {
        var readable: [String: ArcItem] = [:]
        var unreadable: Set<String> = []
        for (key, value) in pairs {
            switch value {
            case .readable(let item):
                if readable[item.id] == nil { readable[item.id] = item }
            case .unreadable:
                if unreadable.insert(key).inserted {
                    warnings.append(.unreadableItem(id: ItemID(rawValue: key)))
                }
            }
        }
        arcItemsByID = readable
        unreadableIDs = unreadable
    }

    /// Adds a root container with the given role. A missing Arc container becomes an empty one.
    mutating func addRoot(_ arcID: String?, role: ContainerRole) -> ItemID {
        guard let arcID, let arcItem = arcItemsByID[arcID], !visited.contains(arcID) else {
            let id = ItemID.make()
            items.append(SidebarItem(id: id, parentID: nil, childIDs: [], title: nil, createdAt: .now, isUnread: false, kind: .container(role)))
            return id
        }
        visited.insert(arcID)
        let id = ItemID(rawValue: arcID)
        let children = addChildren(of: arcItem)
        items.append(SidebarItem(
            id: id,
            parentID: nil,
            childIDs: children,
            title: nil,
            createdAt: date(arcItem.createdAt),
            isUnread: arcItem.isUnread ?? false,
            kind: .container(role)
        ))
        return id
    }

    /// Adds the supported children of `parent` and returns their IDs in order.
    private mutating func addChildren(of parent: ArcItem) -> [ItemID] {
        var childIDs: [ItemID] = []
        for childID in parent.childrenIds ?? [] {
            // Already reported as unreadable.
            if unreadableIDs.contains(childID) { continue }
            guard let child = arcItemsByID[childID], !visited.contains(childID) else {
                warnings.append(.danglingChild(parent: ItemID(rawValue: parent.id), child: ItemID(rawValue: childID)))
                continue
            }
            visited.insert(childID)

            let kind: SidebarItem.Kind
            switch child.data {
            case .tab(let tab):
                kind = .tab(TabInfo(
                    savedURL: tab.savedURL.flatMap(URL.init(string:)),
                    savedTitle: tab.savedTitle,
                    lastActiveAt: tab.timeLastActiveAt.map(Date.init(timeIntervalSinceReferenceDate:)),
                    isMuted: tab.savedMuteStatus == "muted"
                ))
            case .list(let list):
                kind = .folder(FolderInfo(icon: list.customInfo?.iconType?.icon, isExpanded: true))
            case .itemContainer, .unsupported:
                warnings.append(.unsupportedItem(id: ItemID(rawValue: childID), kind: child.data.kindName))
                markSubtreeVisited(child)
                continue
            }

            let grandchildren: [ItemID]
            if case .folder = kind {
                grandchildren = addChildren(of: child)
            } else {
                grandchildren = []
            }
            items.append(SidebarItem(
                id: ItemID(rawValue: childID),
                parentID: ItemID(rawValue: parent.id),
                childIDs: grandchildren,
                title: child.title,
                createdAt: date(child.createdAt),
                isUnread: child.isUnread ?? false,
                kind: kind
            ))
            childIDs.append(ItemID(rawValue: childID))
        }
        return childIDs
    }

    private mutating func markSubtreeVisited(_ item: ArcItem) {
        for childID in item.childrenIds ?? [] where !visited.contains(childID) {
            guard let child = arcItemsByID[childID] else { continue }
            visited.insert(childID)
            markSubtreeVisited(child)
        }
    }

    private func date(_ seconds: Double?) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds ?? 0)
    }
}
