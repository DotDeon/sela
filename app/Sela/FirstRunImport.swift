import AppKit
import ArcImport
import SidebarModel

/// On first launch, offers to bring the user's Arc sidebar into Sela.
@MainActor
enum FirstRunImport {
    /// True once the user picks Start Fresh this launch, so Arc's history is left behind too.
    static private(set) var choseStartFresh = false

    /// The imported sidebar, or nil to start fresh. Asks first, and only when Arc's sidebar file exists.
    static func document() -> SidebarDocument? {
        let fileURL = ArcDataLocation.live.sidebarFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

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
}
