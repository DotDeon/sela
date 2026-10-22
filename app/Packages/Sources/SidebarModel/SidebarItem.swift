import Foundation

/// One node in the sidebar tree: a tab, a folder, or the root container of a section.
public struct SidebarItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case tab(TabInfo)
        case folder(FolderInfo)
        case container(ContainerRole)
    }

    public var id: ItemID
    public var parentID: ItemID?
    public var childIDs: [ItemID]
    public var title: String?
    public var createdAt: Date
    public var isUnread: Bool
    public var kind: Kind

    public init(id: ItemID, parentID: ItemID?, childIDs: [ItemID], title: String?, createdAt: Date, isUnread: Bool, kind: Kind) {
        self.id = id
        self.parentID = parentID
        self.childIDs = childIDs
        self.title = title
        self.createdAt = createdAt
        self.isUnread = isUnread
        self.kind = kind
    }

    var canHaveChildren: Bool {
        switch kind {
        case .tab: false
        case .folder, .container: true
        }
    }

    var isContainer: Bool {
        if case .container = kind { return true }
        return false
    }
}

public struct TabInfo: Codable, Equatable, Sendable {
    public var savedURL: URL?
    public var savedTitle: String?
    public var lastActiveAt: Date?
    public var isMuted: Bool

    public init(savedURL: URL?, savedTitle: String?, lastActiveAt: Date?, isMuted: Bool) {
        self.savedURL = savedURL
        self.savedTitle = savedTitle
        self.lastActiveAt = lastActiveAt
        self.isMuted = isMuted
    }
}

public struct FolderInfo: Codable, Equatable, Sendable {
    public var icon: String?
    public var isExpanded: Bool

    public init(icon: String?, isExpanded: Bool) {
        self.icon = icon
        self.isExpanded = isExpanded
    }
}

/// Which section of the sidebar a container is the root of.
public enum ContainerRole: Codable, Equatable, Sendable {
    case pinned(SpaceID)
    case unpinned(SpaceID)
    case favorites
}
