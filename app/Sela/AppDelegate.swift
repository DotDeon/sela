import AppKit
import Archive
import Browsing
import ContentBlocking
import Downloads
import Favicons
import History
import Sidebar
import SidebarModel
import SidebarUI
import WebKitEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// With `-SelaDataFolder`, cookies, caches and compiled ad blocking rules stay in memory, away from your own.
    private let engine = WebKitEngine(configuration: .init(
        storage: UserDefaults.standard.string(forKey: "SelaDataFolder") == nil ? .persistent : .ephemeral
    ))
    private var sidebar: SidebarStore!
    private var favicons: FaviconStore!
    private var archive: ArchiveStore!
    private var history: HistoryStore?
    private var sweeper: ArchiveSweeper?
    private var tabSleeper: TabSleeper?
    private var settingsWindow: SettingsWindowController?
    /// This session's downloads, shown in every window.
    private let downloads = DownloadList()
    /// `-SelaDataFolder <path>` keeps every Sela file in that folder instead of Application Support,
    /// and skips the Arc import. For measuring runs that mustn't touch your own sidebar.
    private let dataFolderOverride: URL? = UserDefaults.standard.string(forKey: "SelaDataFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
    private var contentBlocker: ContentBlocker!
    /// Nil on systems too old for Web Extensions.
    private var extensions: ExtensionsController?
    private var listRefreshTimer: Timer?
    private var missingListTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var windowControllers: [BrowserWindowController] = []
    /// Links that arrived before launch finished, opened once the first window exists.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        moveDataFromOldName()
        NSApp.mainMenu = MainMenu.make()
        if let dataFolderOverride {
            try? FileManager.default.createDirectory(at: dataFolderOverride, withIntermediateDirectories: true)
        }
        sidebar = SidebarStore(
            fileStore: SidebarDocumentStore(fileURL: dataFile("Sidebar.json") ?? sidebarFileURL()),
            firstRunDocument: dataFolderOverride == nil ? FirstRunImport.document : { nil }
        )
        favicons = FaviconStore(cacheFolder: dataFile("Favicons") ?? (try? FaviconStore.defaultCacheFolder()) ?? FileManager.default.temporaryDirectory)
        archive = ArchiveStore(fileURL: dataFile("Archive.json") ?? (try? ArchiveStore.defaultFileURL()) ?? FileManager.default.temporaryDirectory.appending(path: "Sela-Archive.json"))
        // Sela works without history if the database can't open.
        history = (dataFile("History.sqlite") ?? (try? HistoryStore.defaultFileURL())).flatMap { try? HistoryStore(fileURL: $0) }
        startContentBlocking()
        startExtensions()
        // Start Fresh means nothing from Arc. File > Import History from Arc… still brings it in later.
        if dataFolderOverride == nil, !FirstRunImport.choseStartFresh {
            HistoryImport.runOnFirstLaunch(into: history)
        }

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

        tabSleeper = TabSleeper { [weak self] in self?.windowControllers.map(\.model) ?? [] }
        tabSleeper?.start()

        if let pagesFile = UserDefaults.standard.string(forKey: "SelaOpenPages") {
            openPagesForMeasuring(listedIn: URL(fileURLWithPath: pagesFile))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unfinished downloads would otherwise stay behind as ".download" files.
        engine.discardActiveDownloads()
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

    /// Links and HTML files from other apps, for example when Sela is the default browser.
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
        openWindow(with: [])
    }

    /// A new window with a tab for each address, or the usual first tab when there are none.
    @discardableResult
    private func openWindow(with urls: [URL]) -> BrowserWindowController {
        let controller = BrowserWindowController(engine: engine, sidebar: sidebar, archive: archive, history: history, favicons: favicons,
                                                 contentBlocker: contentBlocker, downloads: downloads, extensions: extensions)
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)
        controller.show(opening: urls)
        return controller
    }

    /// The "Archive Unpinned Tabs After" menu. The item's tag is the number of hours, 0 for never.
    @objc func setArchiveInterval(_ sender: NSMenuItem) {
        ArchiveSweeper.hours = sender.tag
        sweeper?.sweep()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(contentBlocker: contentBlocker, history: history, extensions: extensions) { [weak self] in
                self?.sweeper?.sweep()
                Task { await self?.tabSleeper?.sleepUnusedTabs() }
            }
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func importHistoryFromArc(_ sender: Any?) {
        HistoryImport.runAndReport(into: history, window: NSApp.keyWindow)
    }

    /// The "Sleep Unused Tabs After" menu. The item's tag is the number of minutes, 0 for never.
    @objc func setSleepInterval(_ sender: NSMenuItem) {
        TabSleepSettings().minutes = sender.tag
        Task { await tabSleeper?.sleepUnusedTabs() }
    }

    /// `-SelaOpenPages <file>`: opens each address in the file as a new tab, one every 4 seconds. For measuring runs.
    private func openPagesForMeasuring(listedIn file: URL) {
        let pages = ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            .split(whereSeparator: \.isNewline)
            .compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
        Task { @MainActor [weak self] in
            for page in pages {
                self?.windowControllers.first?.model.newTab(url: page)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Sela > Block Ads and Trackers. Reloads each window's page so the change shows at once.
    @objc func toggleContentBlocking(_ sender: Any?) {
        contentBlocker.setEnabled(!contentBlocker.isEnabled)
        for controller in windowControllers { controller.model.selectedTab?.reload() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setArchiveInterval(_:)) {
            item.state = item.tag == ArchiveSweeper.hours ? .on : .off
        } else if item.action == #selector(setSleepInterval(_:)) {
            item.state = item.tag == TabSleepSettings().minutes ? .on : .off
        } else if item.action == #selector(toggleContentBlocking(_:)) {
            item.state = contentBlocker.isEnabled ? .on : .off
        }
        return true
    }

    // MARK: Content blocking

    /// Installs the lists already downloaded, then checks for new ones now, every 6 hours and after waking,
    /// and every 2 minutes while a list has never downloaded, such as after a first launch with no network.
    private func startContentBlocking() {
        let folder = dataFile("ContentBlocking")
            ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                .map { $0.appending(path: "Sela/ContentBlocking", directoryHint: .isDirectory) }
            ?? FileManager.default.temporaryDirectory.appending(path: "Sela-ContentBlocking")
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

    // MARK: Extensions

    /// Starts the installed Web Extensions. They need macOS 15.4, so older systems don't offer them.
    private func startExtensions() {
        guard engine.supportsExtensions else { return }
        let folder = dataFile("Extensions")
            ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                .map { $0.appending(path: "Sela/Extensions", directoryHint: .isDirectory) }
            ?? FileManager.default.temporaryDirectory.appending(path: "Sela-Extensions")
        extensions = ExtensionsController(engine: engine, folder: folder, windowControllers: { [weak self] in self?.windowControllers ?? [] }) { [unowned self] urls in
            openWindow(with: urls)
        }
        extensions?.start()
    }

    /// Sela was called Brow. Its files move from `Application Support/Brow` to `Application Support/Sela` once,
    /// before anything opens them.
    private func moveDataFromOldName() {
        guard dataFolderOverride == nil,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let old = support.appending(path: "Brow", directoryHint: .isDirectory)
        let new = support.appending(path: "Sela", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) else { return }
        try? FileManager.default.moveItem(at: old, to: new)
    }

    /// A file in the measuring folder from `-SelaDataFolder`, or nil for Sela's usual place.
    private func dataFile(_ name: String) -> URL? {
        dataFolderOverride?.appending(path: name)
    }

    private func sidebarFileURL() -> URL {
        (try? SidebarDocumentStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: "Sela-Sidebar.json")
    }

    private func reportLoadProblem() {
        guard let problem = sidebar.loadProblem else { return }
        let alert = NSAlert()
        switch problem {
        case .corrupt(let backupURL):
            alert.messageText = "Sela couldn't read your sidebar"
            alert.informativeText = "Sela started with an empty sidebar. The unreadable file was kept as \(backupURL.lastPathComponent) in \(backupURL.deletingLastPathComponent().path)."
        case .newerVersion:
            alert.messageText = "Your sidebar was saved by a newer version of Sela"
            alert.informativeText = "This version can't read it, so it's showing an empty sidebar. Changes you make now won't be saved, and your sidebar file is left as it is. Update Sela to get it back."
        case .unreadable(let reason):
            alert.messageText = "Sela couldn't open your sidebar"
            alert.informativeText = "Sela is showing an empty sidebar and won't save changes, so your sidebar file stays safe. Check the file's permissions in ~/Library/Application Support/Sela, then reopen Sela. (\(reason))"
        }
        alert.runModal()
    }
}
