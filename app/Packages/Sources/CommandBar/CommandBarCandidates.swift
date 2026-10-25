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
    /// True for a tab in a space other than the one the window shows. Such a tab is never the top hit, so Enter
    /// stays in the current space, and it comes after this space's tabs when there's no query.
    public var isInAnotherSpace: Bool

    public init(id: ItemID, title: String, url: URL?, lastActiveAt: Date?, location: String? = nil, isInAnotherSpace: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.lastActiveAt = lastActiveAt
        self.location = location
        self.isInAnotherSpace = isInAnotherSpace
    }
}

/// The location a tab's command bar row shows: "Favourites" for favourites, the folders it sits in for a tab
/// in a folder, outermost first, and nil for a tab at the top of its space. From `shownFrom`, another space's
/// tabs start with that space's name.
public func tabLocation(of id: ItemID, in document: SidebarDocument, shownFrom currentSpace: SpaceID? = nil) -> String? {
    var parts = document.folderPath(of: id)
    if document.containerRole(of: id) == .favorites {
        parts.insert("Favourites", at: 0)
    } else if let currentSpace, let spaceID = document.spaceID(containing: id), spaceID != currentSpace {
        parts.insert(document.space(spaceID)?.title ?? "Another Space", at: 0)
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

/// A search on one site from its shortcut, such as `yt cats`.
public struct SiteSearchResult: Equatable, Sendable {
    public var siteName: String
    public var shortcut: String
    public var query: String
    public var url: URL

    public init(siteName: String, shortcut: String, query: String, url: URL) {
        self.siteName = siteName
        self.shortcut = shortcut
        self.query = query
        self.url = url
    }
}

/// A row in the command bar.
public enum CommandBarResult: Equatable, Sendable {
    /// Open what was typed: an address, or a search on `search` when it isn't nil.
    case open(URL, search: SearchEngine?)
    /// Search the site whose shortcut was typed.
    case siteSearch(SiteSearchResult)
    case tab(TabCandidate)
    case command(CommandCandidate)
    case archived(ArchivedCandidate)
    case history(HistoryCandidate)
}
