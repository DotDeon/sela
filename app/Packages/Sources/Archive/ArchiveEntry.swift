import Foundation
import SidebarModel

/// A tab that was closed or archived for inactivity, kept so it can be found and reopened.
public struct ArchiveEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String?
    /// The space the tab was in. Nil for a tab from favourites.
    public var spaceID: SpaceID?
    public var archivedAt: Date

    public init(id: UUID, url: URL?, title: String?, spaceID: SpaceID?, archivedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.spaceID = spaceID
        self.archivedAt = archivedAt
    }
}
