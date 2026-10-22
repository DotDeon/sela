import Foundation

public struct Space: Codable, Equatable, Identifiable, Sendable {
    public var id: SpaceID
    public var title: String?
    public var icon: String?
    public var theme: SpaceTheme?
    public var pinnedContainerID: ItemID
    public var unpinnedContainerID: ItemID

    public init(id: SpaceID, title: String?, icon: String?, theme: SpaceTheme?, pinnedContainerID: ItemID, unpinnedContainerID: ItemID) {
        self.id = id
        self.title = title
        self.icon = icon
        self.theme = theme
        self.pinnedContainerID = pinnedContainerID
        self.unpinnedContainerID = unpinnedContainerID
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
