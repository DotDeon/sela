import Foundation

public struct Space: Codable, Equatable, Identifiable, Sendable {
    public var id: SpaceID
    public var title: String?
    public var icon: String?
    public var theme: SpaceTheme?
    public var pinnedContainerID: ItemID
    public var unpinnedContainerID: ItemID
    /// Whose cookies, logins and site data the space's tabs use.
    public var profileID: ProfileID

    public init(id: SpaceID, title: String?, icon: String?, theme: SpaceTheme?, pinnedContainerID: ItemID, unpinnedContainerID: ItemID,
                profileID: ProfileID = .default) {
        self.id = id
        self.title = title
        self.icon = icon
        self.theme = theme
        self.pinnedContainerID = pinnedContainerID
        self.unpinnedContainerID = unpinnedContainerID
        self.profileID = profileID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, icon, theme, pinnedContainerID, unpinnedContainerID, profileID
    }

    /// Spaces saved before profiles existed use the Default profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(SpaceID.self, forKey: .id),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            icon: try container.decodeIfPresent(String.self, forKey: .icon),
            theme: try container.decodeIfPresent(SpaceTheme.self, forKey: .theme),
            pinnedContainerID: try container.decode(ItemID.self, forKey: .pinnedContainerID),
            unpinnedContainerID: try container.decode(ItemID.self, forKey: .unpinnedContainerID),
            profileID: try container.decodeIfPresent(ProfileID.self, forKey: .profileID) ?? .default
        )
    }
}

public struct SpaceTheme: Codable, Equatable, Sendable {
    public var primary: RGBAColor

    public init(primary: RGBAColor) { self.primary = primary }
}

/// Colour components in 0...1.
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
