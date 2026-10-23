import AppKit
import BrowserEngine
import Browsing
import Favicons
import Sidebar
import SidebarModel
import SidebarUI

/// One browser window: Arc's sidebar on the left and the selected page beside it.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let model: BrowserWindowModel
    var onClose: (() -> Void)?

    private let root: BrowserRootViewController
    private var dialogPresenter: DialogPresenter?

    init(engine: any BrowserEngine, sidebar: SidebarStore, favicons: FaviconStore) {
        model = BrowserWindowModel(engine: engine, sidebar: sidebar)
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

    @objc func newTab(_ sender: Any?) {
        model.newTab(url: nil)
        focusAddressBar(nil)
    }

    @objc func focusAddressBar(_ sender: Any?) {
        root.revealSidebarIfHidden()
        root.sidebarController.focusAddress()
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
