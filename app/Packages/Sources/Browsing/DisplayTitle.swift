import BrowserEngine
import Foundation

/// The name to show for a tab: its page title, or something from its URL when the page has none.
public func displayTitle(for state: TabState) -> String {
    if let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        return title
    }
    guard let url = state.url, url.absoluteString != "about:blank" else { return "New Tab" }
    if url.isFileURL { return url.lastPathComponent }
    return url.host() ?? url.absoluteString
}
