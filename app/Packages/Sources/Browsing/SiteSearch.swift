import Foundation
import RemoteSettings

/// A site you can search from the command bar by typing its shortcut, a space and what to look for:
/// `yt cats` searches YouTube for cats.
public struct SiteSearch: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// What you type before the query. Matched without regard to case.
    public var shortcut: String
    /// The search address, with `%s` where the query goes. Same rules as a search engine's: https, with `%s`.
    public var template: String

    public init(id: UUID = UUID(), name: String, shortcut: String, template: String) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
        self.template = template
    }

    /// The sites Sela ships with.
    public static let defaults: [SiteSearch] = [
        SiteSearch(name: "YouTube", shortcut: "yt", template: "https://www.youtube.com/results?search_query=%s"),
        SiteSearch(name: "GitHub", shortcut: "gh", template: "https://github.com/search?q=%s"),
        SiteSearch(name: "Wikipedia", shortcut: "w", template: "https://en.wikipedia.org/w/index.php?search=%s"),
        SiteSearch(name: "Reddit", shortcut: "r", template: "https://www.reddit.com/search/?q=%s"),
        SiteSearch(name: "Amazon", shortcut: "a", template: "https://www.amazon.com/s?k=%s"),
        SiteSearch(name: "Apple Maps", shortcut: "maps", template: "https://maps.apple.com/?q=%s"),
        SiteSearch(name: "X", shortcut: "tw", template: "https://x.com/search?q=%s"),
    ]

    /// True for a name that isn't blank, a shortcut that's one word, and an https template with `%s`.
    public var isValid: Bool {
        Self.isValidName(name) && Self.isValidShortcut(shortcut) && Self.isValidTemplate(template)
    }

    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    /// One word, up to 20 characters, with no spaces, since a space is what ends the shortcut when you type.
    public static func isValidShortcut(_ shortcut: String) -> Bool {
        !shortcut.isEmpty && shortcut.count <= 20 && !shortcut.contains(where: \.isWhitespace)
    }

    /// The same checks the remote settings put on a search engine's address.
    public static func isValidTemplate(_ template: String) -> Bool {
        RemoteSearchEngine.isValidTemplate(template)
    }

    public func searchURL(for query: String) -> URL? {
        Browsing.searchURL(template: template, query: query)
    }

    /// The site whose shortcut starts `text`, and what to search it for. Nil when `text` doesn't start with a
    /// shortcut, a space and something to look for.
    public static func match(_ text: String, in sites: [SiteSearch]) -> (site: SiteSearch, query: String)? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = text.firstIndex(where: \.isWhitespace) else { return nil }
        let shortcut = text[..<space].lowercased()
        let query = text[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let site = sites.first(where: { $0.shortcut.lowercased() == shortcut }) else { return nil }
        return (site, query)
    }
}

/// The site searches in use, stored in `UserDefaults` as JSON. Until you change them, Sela's defaults apply.
/// A stored list that can't be read falls back to the defaults too, rather than losing the feature.
public struct SiteSearchSettings {
    public static let key = "SiteSearches"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var all: [SiteSearch] {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return SiteSearch.defaults }
            return (try? JSONDecoder().decode([SiteSearch].self, from: data)) ?? SiteSearch.defaults
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key)
        }
    }

    /// Adds a site, or replaces the one with the same id. Only valid sites are kept.
    public func save(_ site: SiteSearch) {
        guard site.isValid else { return }
        var sites = all
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        } else {
            sites.append(site)
        }
        all = sites
    }

    public func remove(_ id: SiteSearch.ID) {
        all = all.filter { $0.id != id }
    }

    /// Back to the sites Sela ships with.
    public func restoreDefaults() {
        defaults.removeObject(forKey: Self.key)
    }
}
