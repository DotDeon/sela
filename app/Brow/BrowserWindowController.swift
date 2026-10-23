import AppKit
import Archive
import BrowserEngine
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
    private let history: HistoryStore?

    init(engine: any BrowserEngine, sidebar: SidebarStore, archive: ArchiveStore, history: HistoryStore?, favicons: FaviconStore) {
        model = BrowserWindowModel(engine: engine, sidebar: sidebar, archive: archive)
        self.history = history
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
        root.sidebarController.onAddressClicked = { [weak self] in self?.focusAddressBar(nil) }
        root.sidebarController.onNewTabClicked = { [weak self] in self?.newTab(nil) }
        keepObserving { [weak self] in self?.updateTitle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows a new window with the sidebar's most recent tab, or a fresh tab when there isn't one.
    func showWithTab() {
        showWindow(nil)
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

    /// Ctrl+Shift+=: a new pane beside the current tab, with the command bar open to choose its page.
    @objc func addSplitView(_ sender: Any?) {
        guard model.addSplitPane() != nil else { return }
        commandBar?.show(.currentTab(address: ""))
    }

    @objc func separateSplitView(_ sender: Any?) { model.separateSelectedSplit() }

    @objc func rotateSplitView(_ sender: Any?) { model.rotateSelectedSplit() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(addSplitView(_:)):
            guard let selected = model.selectedItemID, model.sidebar.document.containerRole(of: selected) != .favorites else { return false }
            return (model.selectedSplit?.paneIDs.count ?? 1) < SidebarDocument.maximumSplitPanes
        case #selector(separateSplitView(_:)), #selector(rotateSplitView(_:)):
            return model.selectedSplit != nil
        default:
            return true
        }
    }

    @objc func closeTab(_ sender: Any?) {
        if let id = model.selectedItemID {
            model.close(id)
        } else {
            window?.performClose(nil)
        }
    }

    @objc func reloadTab(_ sender: Any?) { model.selectedTab?.reload() }

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
        case "new-window": NSApp.sendAction(#selector(AppDelegate.newWindow(_:)), to: nil, from: nil)
        default: break
        }
    }

    private func confirmClearHistory() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear your browsing history?"
        alert.informativeText = "This removes every page Brow remembers you visiting. Your sidebar and archive aren't affected."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.history?.clear() }
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model.closeAllLiveTabs()
        onClose?()
    }

    private func updateTitle() {
        // Hidden in the title bar, but the Window menu and Mission Control use it.
        window?.title = model.selectedTab.map { displayTitle(for: $0.state) } ?? "Brow"
    }
}
