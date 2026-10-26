import AppKit
import Archive
import BrowserEngine
import ContentBlocking
import Downloads
import Browsing
import Favicons
import History
import PageTranslation
import Sidebar
import SidebarModel
import SidebarUI

/// One browser window: Arc's sidebar on the left and the selected page beside it.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: BrowserWindowModel
    var onClose: (() -> Void)?
    /// The area beside the sidebar where pages show.
    var pageArea: NSView { root.pageArea }

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
    private var tabOverview: TabOverviewPresenter?
    private var translator: AppleTranslator?
    private let translationPopover = TranslationPopover()

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
        tabOverview = TabOverviewPresenter(model: model, favicons: favicons, host: root.view)
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
            // A new download opens the list, so you see it start.
            if count > shownCount, self.window?.isKeyWindow == true {
                DispatchQueue.main.async { self.showDownloads(nil) }
            }
            shownCount = count
        }
        root.sidebarController.onAddressClicked = { [weak self] in self?.focusAddressBar(nil) }
        root.sidebarController.onNewTabClicked = { [weak self] in self?.newTab(nil) }
        root.sidebarController.onToggleSidebarClicked = { [weak self] in self?.toggleSidebar(nil) }
        root.sidebarController.onTranslateClicked = { [weak self] anchor in self?.translateButtonClicked(anchor) }
        let translator = AppleTranslator(host: root.view)
        self.translator = translator
        model.translation.translator = translator
        if SidebarSettings().isHidden { root.toggleSidebar() }
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

    /// Tab > Mute Tab: the selected tab's sound off, or back on.
    @objc func toggleMute(_ sender: Any?) { model.toggleMute() }

    /// View > Developer > Show Web Inspector, while developer tools are on in Settings.
    @objc func showWebInspector(_ sender: Any?) { model.selectedTab?.showWebInspector() }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }

    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }

    @objc func resetZoom(_ sender: Any?) { model.resetZoom() }

    // MARK: Printing

    @objc func printPage(_ sender: Any?) { PagePrinting.print(model.selectedTab, in: window) }

    @objc func exportPDF(_ sender: Any?) { PagePrinting.exportPDF(model.selectedTab, in: window) }

    /// Ctrl+Shift+=: a new pane beside the current tab, with the command bar open to choose its page.
    @objc func addSplitView(_ sender: Any?) {
        guard model.addSplitPane() != nil else { return }
        commandBar?.show(.currentTab(address: ""))
    }

    @objc func separateSplitView(_ sender: Any?) { model.separateSelectedSplit() }

    @objc func rotateSplitView(_ sender: Any?) { model.rotateSelectedSplit() }

    /// Tab > Fit Pages in Split View: whether split panes shrink their pages to keep the desktop layout, in every window.
    @objc func toggleSplitFit(_ sender: Any?) {
        let settings = SplitFitSettings()
        settings.fitsPages.toggle()
    }

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
        case #selector(toggleSplitFit(_:)):
            item.state = SplitFitSettings().fitsPages ? .on : .off
            return true
        case #selector(toggleReader(_:)):
            let state = model.selectedTab?.state
            item.state = state?.isShowingReader == true ? .on : .off
            return state?.isReaderAvailable == true || state?.isShowingReader == true
        case #selector(translatePage(_:)):
            guard let translator = model.selectedTranslator else { return false }
            return !translator.status.isActive
        case #selector(showOriginalPage(_:)):
            return model.selectedTranslator?.status.isActive == true
        case #selector(toggleSiteBlocking(_:)):
            guard let url = blockableURL, let contentBlocker else {
                item.state = .off
                return false
            }
            item.state = contentBlocker.isBlocking(on: url) ? .on : .off
            return true
        case #selector(printPage(_:)), #selector(exportPDF(_:)):
            return model.selectedTab?.state.url != nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)):
            return model.selectedTab != nil
        case #selector(toggleMute(_:)):
            item.state = model.selectedTab?.state.isMuted == true ? .on : .off
            return model.selectedTab != nil
        case #selector(showWebInspector(_:)):
            return DeveloperToolsSettings().isEnabled && model.selectedTab?.state.url != nil
        case #selector(resetZoom(_:)):
            guard let zoom = model.selectedTab?.state.pageZoom else { return false }
            return !PageZoom.isActualSize(zoom)
        default:
            return true
        }
    }

    /// View > Tab Overview: every tab in the space as a grid of pictures, or back to the page.
    @objc func toggleTabOverview(_ sender: Any?) { tabOverview?.toggle() }

    @objc func closeTab(_ sender: Any?) {
        if let tabOverview, tabOverview.isShowing {
            tabOverview.closeHighlighted()
        } else if model.peekTab != nil {
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

    // MARK: Translation

    /// View > Translate Page: the page's text in the language from Settings, translated on this Mac.
    @objc func translatePage(_ sender: Any?) {
        guard let translator = model.selectedTranslator, !translator.status.isActive else {
            NSSound.beep()
            return
        }
        Task {
            await translator.translate()
            showTranslationNote(for: translator)
        }
    }

    /// View > Show Original: the page's own text back.
    @objc func showOriginalPage(_ sender: Any?) {
        model.showOriginalSelectedPage()
    }

    /// The Translate button: the offer while the page shows its own text, the original once it's translated.
    private func translateButtonClicked(_ anchor: NSView) {
        guard let translator = model.selectedTranslator else { return }
        if translator.status.isActive {
            translator.showOriginal()
            return
        }
        translationPopover.showOffer(from: translator.sourceLanguage, to: translator.targetLanguage, relativeTo: anchor) { [weak self] in
            self?.translatePage(nil)
        } onDismiss: { [weak self] in
            self?.dismissTranslationOffer()
        }
    }

    private func dismissTranslationOffer() {
        guard let tab = model.selectedTab, let translator = model.selectedTranslator else { return }
        let language = translator.sourceLanguage.displayName
        guard model.translation.dismissOffer(for: tab) else { return }
        translationPopover.showNote("Sela won't offer to translate \(language) again",
                                    "You can change this in Settings > General.", relativeTo: root.sidebarController.translationAnchor)
    }

    /// Says why a page didn't translate, when it didn't.
    private func showTranslationNote(for translator: PageTranslator) {
        guard model.selectedTranslator === translator else { return }
        let pair = "\(translator.sourceLanguage.displayName) to \(translator.targetLanguage.displayName)"
        let anchor = root.sidebarController.translationAnchor
        switch translator.status {
        case .unsupported:
            translationPopover.showNote("This Mac can't translate \(pair)", "Apple's translation doesn't cover this pair of languages yet.", relativeTo: anchor)
        case .downloadNeeded:
            translationPopover.showNote("Translating \(pair) needs a download", "Choose Translate Page again to download the languages.", relativeTo: anchor)
        case .failed:
            translationPopover.showNote("Sela couldn't translate this page", "The page shows its own text. Try again in a moment.", relativeTo: anchor)
        default:
            break
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

    /// Hides or docks the sidebar, and remembers the choice for new windows and the next launch.
    @objc func toggleSidebar(_ sender: Any?) {
        root.toggleSidebar()
        SidebarSettings().isHidden = root.isSidebarHidden
    }

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
        case "translate-page": translatePage(nil)
        case "show-original": showOriginalPage(nil)
        case "tab-overview": toggleTabOverview(nil)
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
