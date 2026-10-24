import AppKit
import BrowserEngine

/// A browser window, as extensions see it: its live tabs in sidebar order and the selected one.
extension BrowserWindowController: ExtensionWindow {
    /// Shows a new window with a tab for each address, or the usual first tab when there are none.
    func show(opening urls: [URL]) {
        for url in urls { model.newTab(url: url) }
        showWithTab()
    }

    var extensionTabs: [any BrowserTab] { model.liveTabsInOrder }

    var activeExtensionTab: (any BrowserTab)? { model.selectedTab }

    func isPinned(_ tab: any BrowserTab) -> Bool { model.isPinned(tab) }

    func activate(_ tab: any BrowserTab) {
        guard let id = model.itemID(for: tab) else { return }
        model.select(id)
        showWindow(nil)
    }

    func close(_ tab: any BrowserTab) {
        guard let id = model.itemID(for: tab) else { return }
        model.close(id)
    }

    var extensionFrame: CGRect { window?.frame ?? .null }

    var extensionScreenFrame: CGRect { window?.screen?.frame ?? .null }

    var isMinimized: Bool { window?.isMiniaturized ?? false }

    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    func focusWindow() {
        showWindow(nil)
        NSApp.activate()
    }

    func closeWindow() {
        window?.performClose(nil)
    }
}
