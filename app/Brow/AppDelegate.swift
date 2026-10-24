import AppKit
import Archive
import ContentBlocking
import Favicons
import History
import Sidebar
import SidebarModel
import SidebarUI
import WebKitEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let engine = WebKitEngine()
    private var sidebar: SidebarStore!
    private var favicons: FaviconStore!
    private var archive: ArchiveStore!
    private var history: HistoryStore?
    private var sweeper: ArchiveSweeper?
    private var contentBlocker: ContentBlocker!
    private var listRefreshTimer: Timer?
    private var missingListTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var windowControllers: [BrowserWindowController] = []
    /// Links that arrived before launch finished, opened once the first window exists.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        sidebar = SidebarStore(fileStore: SidebarDocumentStore(fileURL: sidebarFileURL()), firstRunDocument: FirstRunImport.document)
        favicons = FaviconStore(cacheFolder: (try? FaviconStore.defaultCacheFolder()) ?? FileManager.default.temporaryDirectory)
        archive = ArchiveStore(fileURL: (try? ArchiveStore.defaultFileURL()) ?? FileManager.default.temporaryDirectory.appending(path: "Brow-Archive.json"))
        // Brow works without history if the database can't open.
        history = (try? HistoryStore.defaultFileURL()).flatMap { try? HistoryStore(fileURL: $0) }
        startContentBlocking()

        // Another window may have removed a tab or space this window shows.
        keepObserving { [weak self] in
            guard let self else { return }
            _ = sidebar.document
            for controller in windowControllers { controller.model.reconcile() }
        }

        newWindow(nil)
        NSApp.activate()
        reportLoadProblem()
        if !pendingURLs.isEmpty {
            application(NSApp, open: pendingURLs)
            pendingURLs = []
        }

        sweeper = ArchiveSweeper(sidebar: sidebar, archive: archive) { [weak self] in
            Set(self?.windowControllers.compactMap(\.model.selectedItemID) ?? [])
        }
        sweeper?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in windowControllers { controller.model.markSelectionActive() }
        sidebar?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    /// Links and HTML files from other apps, for example when Brow is the default browser.
    /// Each opens in a new tab in the frontmost window, or in a new window when none is open.
    func application(_ application: NSApplication, open urls: [URL]) {
        let pages = urls.filter { ["http", "https", "file"].contains($0.scheme?.lowercased() ?? "") }
        guard !pages.isEmpty else { return }
        guard sidebar != nil else {
            pendingURLs += pages
            return
        }
        let target = windowControllers.first { $0.window?.isMainWindow == true } ?? windowControllers.last ?? {
            newWindow(nil)
            return windowControllers.last!
        }()
        for page in pages { target.model.newTab(url: page) }
        target.showWindow(nil)
        NSApp.activate()
    }

    @objc func newWindow(_ sender: Any?) {
        let controller = BrowserWindowController(engine: engine, sidebar: sidebar, archive: archive, history: history, favicons: favicons, contentBlocker: contentBlocker)
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)
        controller.showWithTab()
    }

    /// The "Archive Unpinned Tabs After" menu. The item's tag is the number of hours, 0 for never.
    @objc func setArchiveInterval(_ sender: NSMenuItem) {
        ArchiveSweeper.hours = sender.tag
        sweeper?.sweep()
    }

    /// Brow > Block Ads and Trackers. Reloads each window's page so the change shows at once.
    @objc func toggleContentBlocking(_ sender: Any?) {
        contentBlocker.setEnabled(!contentBlocker.isEnabled)
        for controller in windowControllers { controller.model.selectedTab?.reload() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setArchiveInterval(_:)) {
            item.state = item.tag == ArchiveSweeper.hours ? .on : .off
        } else if item.action == #selector(toggleContentBlocking(_:)) {
            item.state = contentBlocker.isEnabled ? .on : .off
        }
        return true
    }

    // MARK: Content blocking

    /// Installs the lists already downloaded, then checks for new ones now, every 6 hours and after waking,
    /// and every 2 minutes while a list has never downloaded, such as after a first launch with no network.
    private func startContentBlocking() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            .map { $0.appending(path: "Brow/ContentBlocking", directoryHint: .isDirectory) }
            ?? FileManager.default.temporaryDirectory.appending(path: "Brow-ContentBlocking")
        let store = FilterListStore(folder: folder, fetch: { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
        contentBlocker = ContentBlocker(engine: engine, store: store, workFolder: folder)
        Task { await contentBlocker.start() }

        listRefreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.contentBlocker.refreshIfNeeded() }
        }
        missingListTimer = Timer.scheduledTimer(withTimeInterval: 2 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let blocker = self?.contentBlocker, blocker.isMissingLists else { return }
                await blocker.refreshIfNeeded()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.contentBlocker.refreshIfNeeded() }
        }
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
