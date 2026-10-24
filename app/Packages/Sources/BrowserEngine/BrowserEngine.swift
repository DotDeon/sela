import Foundation

/// Creates tabs. Sela's UI talks to an engine only through this protocol and `BrowserTab`.
@MainActor
public protocol BrowserEngine: AnyObject {
    /// A new tab, loading `url` when it isn't nil.
    func makeTab(url: URL?) -> any BrowserTab
    /// A tab that picks up where a snapshot left off: same address, history and scroll position where the engine can.
    func makeTab(restoring snapshot: TabSnapshot) -> any BrowserTab
}
