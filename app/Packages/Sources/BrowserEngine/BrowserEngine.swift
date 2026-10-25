import Foundation

/// Names the cookies, logins, site storage and cache a tab uses. Tabs with different profiles share none of them.
public struct ProfileIdentifier: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// The website data Sela used before it had profiles.
    public static let `default` = ProfileIdentifier(rawValue: "default")

    public var description: String { rawValue }
}

/// Creates tabs. Sela's UI talks to an engine only through this protocol and `BrowserTab`.
@MainActor
public protocol BrowserEngine: AnyObject {
    /// Whether pages can be opened in Web Inspector, from their context menu, the View menu or Safari's
    /// Develop menu. Off by default, and a change reaches pages already open.
    var isInspectable: Bool { get set }
    /// A new tab using `profile`'s website data, loading `url` when it isn't nil.
    func makeTab(url: URL?, profile: ProfileIdentifier) -> any BrowserTab
    /// A tab that picks up where a snapshot left off: same address, history and scroll position where the engine can.
    func makeTab(restoring snapshot: TabSnapshot, profile: ProfileIdentifier) -> any BrowserTab
    /// Deletes everything pages stored in `profile`. Close its tabs first. Does nothing for the default profile.
    func removeWebsiteData(of profile: ProfileIdentifier) async
}

extension BrowserEngine {
    /// A new tab using the default profile.
    public func makeTab(url: URL?) -> any BrowserTab {
        makeTab(url: url, profile: .default)
    }

    /// A woken tab using the default profile.
    public func makeTab(restoring snapshot: TabSnapshot) -> any BrowserTab {
        makeTab(restoring: snapshot, profile: .default)
    }
}
