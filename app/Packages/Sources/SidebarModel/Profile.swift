import Foundation

/// A set of cookies, logins, site storage and cache. Each space uses one, so two spaces can be signed in
/// to different accounts on the same site. Favourites, history and the archive are shared by every profile.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: ProfileID
    public var name: String
    /// An emoji, or the name of an SF Symbol.
    public var icon: String?
    public var color: RGBAColor?

    public init(id: ProfileID, name: String, icon: String? = nil, color: RGBAColor? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }

    public static let defaultName = "Default"

    public var isDefault: Bool { id == .default }
}
