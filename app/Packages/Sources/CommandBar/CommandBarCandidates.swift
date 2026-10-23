import Foundation
import SidebarModel

/// A sidebar tab the command bar can switch to.
public struct TabCandidate: Equatable, Sendable {
    public var id: ItemID
    public var title: String
    public var url: URL?
    public var lastActiveAt: Date?

    public init(id: ItemID, title: String, url: URL?, lastActiveAt: Date?) {
        self.id = id
        self.title = title
        self.url = url
        self.lastActiveAt = lastActiveAt
    }
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
    /// Open what was typed: an address, or a search when `isSearch`.
    case open(URL, isSearch: Bool)
    case tab(TabCandidate)
    case command(CommandCandidate)
    case archived(ArchivedCandidate)
    case history(HistoryCandidate)
}
