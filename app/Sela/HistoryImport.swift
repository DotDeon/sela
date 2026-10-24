import AppKit
import ArcImport
import History

/// Brings Arc's browsing history from the last 90 days into Sela's history.
@MainActor
enum HistoryImport {
    static let doneKey = "ArcHistoryImported"

    /// Imports and returns how many pages came across. Records that the import happened.
    @discardableResult
    static func run(into history: HistoryStore) -> Int {
        let visits = readArcHistory(from: .live, since: Date().addingTimeInterval(-90 * 86_400))
        let entries = visits.map { HistoryEntry(url: $0.url, title: $0.title, visitCount: $0.visitCount, lastVisitedAt: $0.lastVisitedAt) }
        history.importVisits(entries)
        UserDefaults.standard.set(true, forKey: doneKey)
        return entries.count
    }

    /// File > Import History from Arc… and the Settings button: imports and says how it went.
    static func runAndReport(into history: HistoryStore?, window: NSWindow?) {
        let alert = NSAlert()
        if let history {
            let count = run(into: history)
            alert.messageText = count == 0 ? "Arc has no history to import" : "Imported \(count) pages from Arc"
            alert.informativeText = count == 0 ? "Sela looked for Arc's history and found nothing from the last 90 days." : "They're in the command bar's history results now."
        } else {
            alert.messageText = "Sela's history isn't available"
            alert.informativeText = "Sela couldn't open its history file, so there's nowhere to import Arc's history to."
        }
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// On first launch, imports quietly once if Arc has history.
    static func runOnFirstLaunch(into history: HistoryStore?) {
        guard let history, !UserDefaults.standard.bool(forKey: doneKey), !ArcDataLocation.live.historyFileURLs.isEmpty else { return }
        run(into: history)
    }
}
