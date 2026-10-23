import AppKit
import Favicons
import Sidebar
import SidebarModel
import SidebarUI
import WebKitEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = WebKitEngine()
    private var sidebar: SidebarStore!
    private var favicons: FaviconStore!
    private var windowControllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        sidebar = SidebarStore(fileStore: SidebarDocumentStore(fileURL: sidebarFileURL()), firstRunDocument: FirstRunImport.document)
        favicons = FaviconStore(cacheFolder: (try? FaviconStore.defaultCacheFolder()) ?? FileManager.default.temporaryDirectory)

        // Another window may have removed a tab or space this window shows.
        keepObserving { [weak self] in
            guard let self else { return }
            _ = sidebar.document
            for controller in windowControllers { controller.model.reconcile() }
        }

        newWindow(nil)
        NSApp.activate()
        reportLoadProblem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sidebar?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    @objc func newWindow(_ sender: Any?) {
        let controller = BrowserWindowController(engine: engine, sidebar: sidebar, favicons: favicons)
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)
        controller.showWithTab()
    }

    private func sidebarFileURL() -> URL {
        (try? SidebarDocumentStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: "Brow-Sidebar.json")
    }

    private func reportLoadProblem() {
        guard let problem = sidebar.loadProblem else { return }
        let alert = NSAlert()
        switch problem {
        case .corrupt(let backupURL):
            alert.messageText = "Brow couldn't read your sidebar"
            alert.informativeText = "Brow started with an empty sidebar. The unreadable file was kept as \(backupURL.lastPathComponent) in \(backupURL.deletingLastPathComponent().path)."
        case .newerVersion:
            alert.messageText = "Your sidebar was saved by a newer version of Brow"
            alert.informativeText = "This version can't read it, so it's showing an empty sidebar. Changes you make now won't be saved, and your sidebar file is left as it is. Update Brow to get it back."
        case .unreadable(let reason):
            alert.messageText = "Brow couldn't open your sidebar"
            alert.informativeText = "Brow is showing an empty sidebar and won't save changes, so your sidebar file stays safe. Check the file's permissions in ~/Library/Application Support/Brow, then reopen Brow. (\(reason))"
        }
        alert.runModal()
    }
}
