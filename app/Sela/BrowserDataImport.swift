import AppKit
import BrowserImport
import History
import Sidebar
import SidebarModel

/// Brings bookmarks and the last 90 days of history in from Chrome, Brave, Edge or Safari.
@MainActor
enum BrowserDataImport {
    struct Outcome {
        var bookmarks: BookmarkImportCount
        var pages: Int
    }

    static var historyCutoff: Date { Date().addingTimeInterval(-90 * 86_400) }

    /// Reads the profile away from the main thread, then adds its bookmarks to the space's pinned section and its
    /// history to Sela's. Throws `BrowserImportError.needsFullDiskAccess` when macOS blocks the read.
    static func run(_ profile: BrowserProfile, sidebar: SidebarStore, space: SpaceID?, history: HistoryStore?) async throws -> Outcome {
        let cutoff = historyCutoff
        let data = try await Task.detached { try readBrowserData(from: profile, historySince: cutoff) }.value
        let spaceID = space.flatMap { sidebar.document.space($0)?.id } ?? sidebar.document.spaces[0].id
        let counts = sidebar.edit { $0.addPinnedBookmarks(data.bookmarks, in: spaceID, now: .now) }
        let entries = historyEntries(data.visits)
        history?.importVisits(entries)
        return Outcome(bookmarks: counts, pages: history == nil ? 0 : entries.count)
    }

    static func historyEntries(_ visits: [ImportedVisit]) -> [HistoryEntry] {
        visits.map { HistoryEntry(url: $0.url, title: $0.title, visitCount: $0.visitCount, lastVisitedAt: $0.lastVisitedAt) }
    }

    /// The profile the user most likely means: the default browser's, otherwise the one used most recently.
    static func mostLikely(among profiles: [BrowserProfile]) -> BrowserProfile? {
        let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        let candidates = profiles.filter { $0.browser.bundleIdentifier == defaultBrowser }
        return (candidates.isEmpty ? profiles : candidates).max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }
    }

    /// What came in, in a sentence or two.
    static func summary(_ outcome: Outcome, from browser: Browser) -> String {
        let tabs = outcome.bookmarks.tabs, folders = outcome.bookmarks.folders
        guard tabs > 0 || outcome.pages > 0 else {
            return "Nothing new came in from \(browser.name). Its bookmarks are already pinned here or it has none, and it has no history from the last 90 days."
        }
        var parts: [String] = []
        if tabs > 0 {
            let folderText = folders > 0 ? " and \(count(folders, "folder"))" : ""
            parts.append("Added \(count(tabs, "pinned tab"))\(folderText) to the space you're in.")
        } else {
            parts.append("No new bookmarks came in. They're already pinned here, or \(browser.name) has none.")
        }
        if outcome.pages > 0 {
            parts.append("Brought in \(count(outcome.pages, "page")) of history.")
        }
        return parts.joined(separator: " ")
    }

    static let fullDiskAccessExplanation = "macOS only lets Sela read Safari's bookmarks and history once you give Sela Full Disk Access. Turn Sela on in Full Disk Access, then import again."

    /// System Settings at Privacy & Security > Full Disk Access.
    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number.formatted()) \(noun)\(number == 1 ? "" : "s")"
    }
}
