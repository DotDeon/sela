import BrowserEngine
import Observation

/// What a window's dialog sheet, find bar and page menus need from it: the page in front, every page it holds,
/// and the dialogs the page in front is waiting on.
@MainActor
public protocol PageWindowModel: AnyObject, Observable {
    var selectedTab: (any BrowserTab)? { get }
    /// Every live page the window holds, the page in front included.
    var openTabs: [any BrowserTab] { get }
    /// The oldest dialog from the page in front.
    var dialogForSelectedTab: PendingDialog? { get }
    /// Where each site's zoom level is kept.
    var zoomStore: PageZoomStore { get }
    func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult)
}

// MARK: Sound

extension PageWindowModel {
    /// Tab > Mute Tab: turns the page in front's sound off, or back on.
    public func toggleMute() {
        guard let tab = selectedTab else { return }
        tab.setMuted(!tab.state.isMuted)
    }
}

// MARK: Zoom

extension PageWindowModel {
    /// View > Zoom In: the next step up for the page in front, kept for its site.
    public func zoomIn() {
        guard let tab = selectedTab else { return }
        setZoom(PageZoom.zoomedIn(from: tab.state.pageZoom))
    }

    /// View > Zoom Out: the next step down for the page in front, kept for its site.
    public func zoomOut() {
        guard let tab = selectedTab else { return }
        setZoom(PageZoom.zoomedOut(from: tab.state.pageZoom))
    }

    /// View > Actual Size: back to 100 percent, which forgets the site's level.
    public func resetZoom() {
        setZoom(1)
    }

    /// Shows the page in front, and every other page on its site, at `zoom`, and keeps that for the site.
    public func setZoom(_ zoom: Double) {
        guard let tab = selectedTab else { return }
        let url = tab.state.url
        // The store first, so the state change each page reports finds the level it was just given.
        zoomStore.setZoom(zoom, for: url)
        tab.setPageZoom(zoom)
        for other in openTabs where other !== tab && PageZoomStore.sameSite(other.state.url, url) {
            other.setPageZoom(zoom)
        }
    }

    /// Puts a page at the level kept for its site. Call whenever a page's state changes, so a new page, a page
    /// that moved to another site, and a page that woke all show at the size the site was left at.
    public func applyRememberedZoom(to tab: any BrowserTab) {
        let wanted = zoomStore.zoom(for: tab.state.url)
        if tab.state.pageZoom != wanted {
            tab.setPageZoom(wanted)
        }
    }
}
