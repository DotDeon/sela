import AppKit
import Archive
import BrowserEngine
import ContentBlocking
import Downloads
import Browsing
import Favicons
import History
import Sidebar
import SidebarModel
import SidebarUI

/// One browser window: Arc's sidebar on the left and the selected page beside it.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: BrowserWindowModel
    var onClose: (() -> Void)?

    private let root: BrowserRootViewController
    private var dialogPresenter: DialogPresenter?
    private var commandBar: CommandBarPresenter?
    private var peek: PeekPresenter?
    private let history: HistoryStore?
    private let contentBlocker: ContentBlocker?
    private var findBar: FindBarController?
    private var downloadsPopover: DownloadsPopover?
    private let extensions: ExtensionsController?
    private var pictureInPicture: PictureInPictureController?

    init(engine: any BrowserEngine, sidebar: SidebarStore, archive: ArchiveStore, history: HistoryStore?, favicons: FaviconStore,
         contentBlocker: ContentBlocker?, downloads: DownloadList, extensions: ExtensionsController?) {
        model = BrowserWindowModel(engine: engine, sidebar: sidebar, archive: archive, downloads: downloads)
        self.history = history
        self.contentBlocker = contentBlocker
        self.extensions = extensions
        root = BrowserRootViewController(model: model, favicons: favicons)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 600, height: 400)
        super.init(window: window)

        window.contentViewController = root
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.center()
        window.setFrameAutosaveName("BrowserWindow")
        window.delegate = self

        dialogPresenter = DialogPresenter(model: model, window: window)
        model.onPageVisited = { [weak history] url, title in history?.recordVisit(url: url, title: title) }
        commandBar = CommandBarPresenter(model: model, history: history, favicons: favicons, host: root.view) { [weak self] id in
            self?.runCommand(id)
        }
        peek = PeekPresenter(model: model, host: root.pageArea)
        pictureInPicture = PictureInPictureController(model: model, window: window)
        findBar = FindBarController(model: model, host: root.pageArea)
        let popover = DownloadsPopover(list: downloads)
        downloadsPopover = popover
        root.sidebarController.onDownloadsClicked = { [weak self] in self?.showDownloads(nil) }
        model.onChooseFiles = { [weak self] multiple, folders in await PagePrompts.chooseFiles(in: self?.window, multiple: multiple, folders: folders) }
        model.onCaptureRequest = { [weak self] media, origin in await PagePrompts.askToCapture(media, origin: origin, in: self?.window) }
        var shownCount = downloads.downloads.count
        keepObserving { [weak self] in
            guard let self else { return }
            let count = downloads.downloads.count
            root.sidebarController.showsDownloadsButton = count > 0
            // A new download opens the list, so you see it start.
            if count > shownCount, self.window?.isKeyWindow == true {
                DispatchQueue.main.async { self.showDownloads(nil) }
            }
            shownCount = count
        }
        root.sidebarController.onAddressClicked = { [weak self] in self?.focusAddressBar(nil) }
        root.sidebarController.onNewTabClicked = { [weak self] in self?.newTab(nil) }
        keepObserving { [weak self] in self?.updateTitle() }
        if let extensions { connect(extensions) }
    }

    var sidebarController: SidebarViewController { root.sidebarController }

    func revealSidebarForExtensions() { root.revealSidebarIfHidden() }

    /// Shows the extensions' buttons and tells them which tab is selected.
    private func connect(_ extensions: ExtensionsController) {
        root.sidebarController.onExtensionClicked = { [weak self] item, anchor in
            guard let self else { return }
            extensions.performAction(of: item, in: self, anchor: anchor)
        }
        root.sidebarController.onManageExtensions = {
            NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        }
        keepObserving { [weak self] in
            guard let self else { return }
            root.sidebarController.extensions = extensions.library.running
        }
        var previous: (any BrowserTab)?
        keepObserving { [weak self] in
            guard let self else { return }
            let tab = model.selectedTab
            guard tab !== previous else { return }
            if let tab { extensions.tabDidActivate(tab, previous: previous) }
            previous = tab
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows a new window with the sidebar's most recent tab, or a fresh tab when there isn't one.
    func showWithTab() {
        showWindow(nil)
        extensions?.windowDidOpen(self)
        if model.selectedItemID == nil {
            newTab(nil)
        }
    }

    // MARK: Actions

    /// Cmd+T: the command bar, opening what's chosen in a new tab.
    @objc func newTab(_ sender: Any?) {
        commandBar?.show(.newTab)
    }

    /// Cmd+L: the command bar, starting with the current address.
    @objc func focusAddressBar(_ sender: Any?) {
        let address = model.selectedTab?.state.url?.absoluteString ?? ""
        commandBar?.show(.currentTab(address: address == "about:blank" ? "" : address))
    }

    @objc func reopenArchivedTab(_ sender: Any?) { model.reopenLastArchived() }

    // MARK: Find, downloads, files and permissions

    @objc func showFindBar(_ sender: Any?) { findBar?.show() }

    @objc func findNextInPage(_ sender: Any?) { findBar?.findNext() }

    @objc func findPreviousInPage(_ sender: Any?) { findBar?.findPrevious() }

    @objc func showDownloads(_ sender: Any?) {
        root.revealSidebarIfHidden()
        downloadsPopover?.show(relativeTo: root.sidebarController.downloadsButton)
    }

    /// Ctrl+Shift+=: a new pane beside the current tab, with the command bar open to choose its page.
    @objc func addSplitView(_ sender: Any?) {
        guard model.addSplitPane() != nil else { return }
        commandBar?.show(.currentTab(address: ""))
    }

    @objc func separateSplitView(_ sender: Any?) { model.separateSelectedSplit() }

    @objc func rotateSplitView(_ sender: Any?) { model.rotateSelectedSplit() }

    /// Tab > Block Ads on This Site. Reloads the page so the change shows at once.
    @objc func toggleSiteBlocking(_ sender: Any?) {
        guard let contentBlocker, let url = blockableURL else { return }
        contentBlocker.setBlocking(!contentBlocker.isBlocking(on: url), forSiteOf: url)
        model.selectedTab?.reload()
    }

    /// The selected page's address when site blocking can be switched there: a web page, with blocking on globally.
    private var blockableURL: URL? {
        guard contentBlocker?.isEnabled == true, let url = model.selectedTab?.state.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(addSplitView(_:)):
            guard let selected = model.selectedItemID, model.sidebar.document.containerRole(of: selected) != .favorites else { return false }
            return (model.selectedSplit?.paneIDs.count ?? 1) < SidebarDocument.maximumSplitPanes
        case #selector(separateSplitView(_:)), #selector(rotateSplitView(_:)):
            return model.selectedSplit != nil
        case #selector(toggleReader(_:)):
            let state = model.selectedTab?.state
            item.state = state?.isShowingReader == true ? .on : .off
            return state?.isReaderAvailable == true || state?.isShowingReader == true
        case #selector(toggleSiteBlocking(_:)):
            guard let url = blockableURL, let contentBlocker else {
                item.state = .off
                return false
            }
            item.state = contentBlocker.isBlocking(on: url) ? .on : .off
            return true
        default:
            return true
        }
    }

    @objc func closeTab(_ sender: Any?) {
        if model.peekTab != nil {
            model.closePeek()
        } else if let id = model.selectedItemID {
            model.close(id)
        } else {
            window?.performClose(nil)
        }
    }

    @objc func reloadTab(_ sender: Any?) { model.selectedTab?.reload() }

    /// View > Reader: the page's article in a plain layout, or back to the page.
    @objc func toggleReader(_ sender: Any?) {
        Task {
            if await !model.toggleReader() { NSSound.beep() }
        }
    }

    @objc func stopTab(_ sender: Any?) { model.selectedTab?.stopLoading() }

    @objc func goBackInTab(_ sender: Any?) { model.selectedTab?.goBack() }

    @objc func goForwardInTab(_ sender: Any?) { model.selectedTab?.goForward() }

    @objc func selectNextTab(_ sender: Any?) { model.selectNext() }

    @objc func selectPreviousTab(_ sender: Any?) { model.selectPrevious() }

    @objc func selectTabByNumber(_ sender: NSMenuItem) { model.select(number: sender.tag) }

    @objc func togglePin(_ sender: Any?) {
        if let id = model.selectedItemID { model.togglePin(id) }
    }

    @objc func newFolder(_ sender: Any?) {
        root.revealSidebarIfHidden()
        root.sidebarController.newFolder()
    }

    @objc func copyURL(_ sender: Any?) {
        guard let url = model.selectedTab?.state.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc func toggleSidebar(_ sender: Any?) { root.toggleSidebar() }

    @objc func selectNextSpace(_ sender: Any?) { model.selectNextSpace() }

    @objc func selectPreviousSpace(_ sender: Any?) { model.selectPreviousSpace() }

    @objc func selectSpaceByNumber(_ sender: NSMenuItem) { model.selectSpace(number: sender.tag) }

    @objc func newSpace(_ sender: Any?) {
        let id = model.sidebar.addSpace(title: "New Space")
        model.selectSpace(id)
    }

    private func runCommand(_ id: String) {
        switch id {
        case "new-space": newSpace(nil)
        case "toggle-sidebar": toggleSidebar(nil)
        case "copy-url": copyURL(nil)
        case "pin-tab": togglePin(nil)
        case "clear-unpinned": model.clearUnpinned()
        case "reopen-archived": model.reopenLastArchived()
        case "clear-history": confirmClearHistory()
        case "add-split": addSplitView(nil)
        case "separate-split": separateSplitView(nil)
        case "rotate-split": rotateSplitView(nil)
        case "toggle-site-blocking": toggleSiteBlocking(nil)
        case "toggle-reader": toggleReader(nil)
        case "new-window": NSApp.sendAction(#selector(AppDelegate.newWindow(_:)), to: nil, from: nil)
        default: break
        }
    }

    private func confirmClearHistory() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear your browsing history?"
        alert.informativeText = "This removes every page Sela remembers you visiting. Your sidebar and archive aren't affected."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.history?.clear() }
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        extensions?.windowDidClose(self)
        model.closeAllLiveTabs()
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        extensions?.windowDidFocus(self)
    }

    private func updateTitle() {
        // Hidden in the title bar, but the Window menu and Mission Control use it.
        window?.title = model.selectedTab.map { displayTitle(for: $0.state) } ?? "Sela"
    }
}
