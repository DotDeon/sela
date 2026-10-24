import Foundation

/// The whole sidebar: spaces in display order, the profiles they use, the shared favourites, and every item.
public struct SidebarDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var spaces: [Space]
    /// Default first, then the others in the order they were made.
    public internal(set) var profiles: [Profile]
    public var favoritesContainerID: ItemID
    var itemsByID: [ItemID: SidebarItem]

    /// Adds the Default profile when `profiles` lacks it, and gives spaces whose profile is missing the Default one.
    public init(version: Int, spaces: [Space], favoritesContainerID: ItemID, items: [SidebarItem], profiles: [Profile] = []) {
        self.version = version
        self.favoritesContainerID = favoritesContainerID
        self.itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        var seen: Set<ProfileID> = []
        var known = profiles.filter { seen.insert($0.id).inserted }
        if let index = known.firstIndex(where: \.isDefault) {
            known.insert(known.remove(at: index), at: 0)
        } else {
            known.insert(Profile(id: .default, name: Profile.defaultName), at: 0)
            seen.insert(.default)
        }
        self.profiles = known
        self.spaces = spaces.map { space in
            var space = space
            if !seen.contains(space.profileID) { space.profileID = .default }
            return space
        }
    }

    /// A document with one untitled space and empty favourites.
    public static func empty(now: Date) -> SidebarDocument {
        let spaceID = SpaceID.make()
        let favorites = SidebarItem(id: .make(), parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(.favorites))
        let pinned = SidebarItem(id: .make(), parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(.pinned(spaceID)))
        let unpinned = SidebarItem(id: .make(), parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(.unpinned(spaceID)))
        let space = Space(id: spaceID, title: nil, icon: nil, theme: nil, pinnedContainerID: pinned.id, unpinnedContainerID: unpinned.id)
        return SidebarDocument(version: currentVersion, spaces: [space], favoritesContainerID: favorites.id, items: [favorites, pinned, unpinned])
    }

    public func item(_ id: ItemID) -> SidebarItem? { itemsByID[id] }

    public func children(of id: ItemID) -> [SidebarItem] {
        (itemsByID[id]?.childIDs ?? []).compactMap { itemsByID[$0] }
    }

    /// Every item, sorted by ID so output is stable.
    public var allItems: [SidebarItem] {
        itemsByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case version, spaces, profiles, favoritesContainerID, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            spaces: try container.decode([Space].self, forKey: .spaces),
            favoritesContainerID: try container.decode(ItemID.self, forKey: .favoritesContainerID),
            items: try container.decode([SidebarItem].self, forKey: .items),
            // Sidebars saved before profiles existed have none, so every space gets Default.
            profiles: try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(spaces, forKey: .spaces)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(favoritesContainerID, forKey: .favoritesContainerID)
        try container.encode(allItems, forKey: .items)
    }
}
