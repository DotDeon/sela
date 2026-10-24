import AppKit
import ArcImport
import BrowserImport
import History
import SidebarModel

/// On first launch, offers to bring the user's Arc sidebar into Sela. Without Arc, offers bookmarks and history
/// from Chrome, Brave, Edge or Safari instead.
@MainActor
enum FirstRunImport {
    /// True once the user picks Start Fresh this launch, so Arc's history is left behind too.
    static private(set) var choseStartFresh = false
    /// History read from another browser, waiting for Sela's history store to open.
    static private var pendingHistory: [HistoryEntry] = []

    /// The imported sidebar, or nil to start fresh. Asks first, and only when there's something to import.
    static func document() -> SidebarDocument? {
        let fileURL = ArcDataLocation.live.sidebarFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return browserDocument() }

        NSApp.activate()
        let offer = NSAlert()
        offer.messageText = "Bring your Arc sidebar into Sela?"
        offer.informativeText = "Sela can copy your spaces, pinned tabs, folders and favourites from Arc. Arc isn't changed. Your browsing history from the last 90 days comes across too. Passwords stay with Arc: export them from Arc's settings."
        offer.addButton(withTitle: "Import")
        offer.addButton(withTitle: "Start Fresh")
        guard offer.runModal() == .alertFirstButtonReturn else {
            choseStartFresh = true
            return nil
        }

        do {
            return try ArcSidebarImporter().importSidebar(from: fileURL).document
        } catch {
            let failure = NSAlert()
            failure.messageText = "Sela couldn't read Arc's sidebar"
            failure.informativeText = "Sela will start with an empty sidebar. (\(error.localizedDescription))"
            failure.runModal()
            return nil
        }
    }

    /// Adds the history read on first launch, once Sela's history store is open.
    static func importPendingHistory(into history: HistoryStore?) {
        guard let history, !pendingHistory.isEmpty else { return }
        history.importVisits(pendingHistory)
        pendingHistory = []
    }

    /// Offers the browser the user most likely uses, with a menu of the others when there are any. Each browser
    /// stands for its most recently used profile, and Settings can import the rest.
    private static func browserDocument() -> SidebarDocument? {
        let found = Dictionary(grouping: BrowserLocations.live.profiles(), by: \.browser)
        let choices = Browser.allCases.compactMap { found[$0].flatMap(BrowserDataImport.mostLikely(among:)) }
        guard let likely = BrowserDataImport.mostLikely(among: choices) else { return nil }

        NSApp.activate()
        let offer = NSAlert()
        let menu = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26), pullsDown: false)
        if choices.count > 1 {
            menu.addItems(withTitles: choices.map(\.browser.name))
            menu.selectItem(withTitle: likely.browser.name)
            offer.accessoryView = menu
            offer.messageText = "Bring your bookmarks into Sela?"
            offer.informativeText = "Sela can add the bookmarks bar from the browser you pick as pinned tabs and folders, along with your browsing history from the last 90 days. That browser isn't changed."
        } else {
            offer.messageText = "Bring your \(likely.browser.name) bookmarks into Sela?"
            offer.informativeText = "Sela can add your \(likely.browser.name) bookmarks bar as pinned tabs and folders, along with your browsing history from the last 90 days. \(likely.browser.name) isn't changed."
        }
        offer.addButton(withTitle: "Import")
        offer.addButton(withTitle: "Start Fresh")
        guard offer.runModal() == .alertFirstButtonReturn else {
            choseStartFresh = true
            return nil
        }
        let profile = choices.count > 1 ? choices[max(menu.indexOfSelectedItem, 0)] : likely

        do {
            let data = try readBrowserData(from: profile, historySince: BrowserDataImport.historyCutoff)
            var document = SidebarDocument.empty(now: .now)
            document.addPinnedBookmarks(data.bookmarks, in: document.spaces[0].id, now: .now)
            pendingHistory = BrowserDataImport.historyEntries(data.visits)
            return document
        } catch BrowserImportError.needsFullDiskAccess {
            let failure = NSAlert()
            failure.messageText = "Sela needs Full Disk Access to read \(profile.browser.name)"
            failure.informativeText = "macOS only lets Sela read \(profile.browser.name)'s bookmarks and history once you give Sela Full Disk Access. Sela will start with an empty sidebar. Turn Sela on in Full Disk Access, then import from Settings."
            failure.addButton(withTitle: "Open System Settings")
            failure.addButton(withTitle: "Continue")
            if failure.runModal() == .alertFirstButtonReturn {
                BrowserDataImport.openFullDiskAccessSettings()
            }
            return nil
        } catch {
            let failure = NSAlert()
            failure.messageText = "Sela couldn't read \(profile.browser.name)'s bookmarks"
            failure.informativeText = "Sela will start with an empty sidebar. (\(error.localizedDescription))"
            failure.runModal()
            return nil
        }
    }
}
