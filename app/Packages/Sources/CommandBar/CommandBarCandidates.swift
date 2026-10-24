import Browsing
import Foundation
import SidebarModel

/// A sidebar tab the command bar can switch to.
public struct TabCandidate: Equatable, Sendable {
    public var id: ItemID
    public var title: String
    public var url: URL?
    public var lastActiveAt: Date?
    /// Where the tab sits, such as "Favourites" or "Work / Projects", for tabs in a folder or among favourites.
    /// Nil for tabs at the top of a space. Its words find the tab too.
    public var location: String?

    public init(id: ItemID, title: String, url: URL?, lastActiveAt: Date?, location: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.lastActiveAt = lastActiveAt
        self.location = location
    }
}

/// The location a tab's command bar row shows: "Favourites" for favourites, the folders it sits in for a tab
/// in a folder, outermost first, and nil for a tab at the top of its space.
public func tabLocation(of id: ItemID, in document: SidebarDocument) -> String? {
    var parts = document.folderPath(of: id)
    if document.containerRole(of: id) == .favorites {
        parts.insert("Favourites", at: 0)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " / ")
}

/// Something the command bar can do, like "New Space".
public struct CommandCandidate: Equatable, Sendable {
    public var id: String
    public var title: String
    /// Extra words that find this command.
    public var keywords: [String]

    public init(id: String, title: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.keywords = keywords
    }
}

/// An archived tab the command bar can restore.
public struct ArchivedCandidate: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?

    public init(id: UUID, title: String, url: URL?) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// A page from history the command bar can open.
public struct HistoryCandidate: Equatable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

/// A row in the command bar.
public enum CommandBarResult: Equatable, Sendable {
    /// Open what was typed: an address, or a search on `search` when it isn't nil.
    case open(URL, search: SearchEngine?)
    case tab(TabCandidate)
    case command(CommandCandidate)
    case archived(ArchivedCandidate)
    case history(HistoryCandidate)
}
