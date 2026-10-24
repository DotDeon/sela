import Foundation
import SidebarModel

/// A tab that was closed or archived for inactivity, kept so it can be found and reopened.
public struct ArchiveEntry: Codable, Equatable, Identifiable, Sendable {
    /// Why the tab left the sidebar.
    public enum Reason: String, Codable, Sendable {
        /// The user closed it, or cleared it with the rest of the unpinned tabs.
        case closed
        /// Sela archived it after it went unused for the archive interval.
        case inactive
    }

    public var id: UUID
    public var url: URL?
    public var title: String?
    /// The space the tab was in. Nil for a tab from favourites.
    public var spaceID: SpaceID?
    public var archivedAt: Date
    public var reason: Reason

    public init(id: UUID, url: URL?, title: String?, spaceID: SpaceID?, archivedAt: Date, reason: Reason = .closed) {
        self.id = id
        self.url = url
        self.title = title
        self.spaceID = spaceID
        self.archivedAt = archivedAt
        self.reason = reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        spaceID = try container.decodeIfPresent(SpaceID.self, forKey: .spaceID)
        archivedAt = try container.decode(Date.self, forKey: .archivedAt)
        // Archives saved before reasons existed only held closed tabs that were worth reopening.
        reason = try container.decodeIfPresent(Reason.self, forKey: .reason) ?? .closed
    }
}
