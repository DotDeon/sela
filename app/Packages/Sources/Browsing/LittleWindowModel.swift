import Archive
import BrowserEngine
import Downloads
import Foundation
import Observation

/// One Little Sela window: a single page, outside the sidebar, for a link another app opened.
/// It can move to a main window's tabs with `takeTab()`. Closed, it goes to the archive like a closed unpinned tab.
@MainActor
@Observable
public final class LittleWindowModel: BrowserTabDelegate, PageWindowModel {
    /// Where the page goes when the window closes. Nil keeps no archive.
    public let archive: ArchiveStore?
    /// This session's downloads, shared with every window.
    public let downloads: DownloadList?
    /// Called once each time the page finishes loading a new web address, with the title it has then.
    @ObservationIgnored public var onPageVisited: ((URL, String?) -> Void)?
    /// Asks the user for files to upload. Gets whether several files, and folders, are allowed. Nil means cancelled.
    @ObservationIgnored public var onChooseFiles: (@MainActor (Bool, Bool) async -> [URL]?)?
    /// Asks the user whether a site may use the camera or microphone. Only called when there's no remembered choice.
    @ObservationIgnored public var onCaptureRequest: (@MainActor (MediaCapture, URL) async -> Bool)?
    /// Where downloads go. Defaults to the user's Downloads folder.
    @ObservationIgnored public var downloadsFolder: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    /// Takes a page this page opened, such as a popup or a Cmd-clicked link. Without it the new page is closed.
    @ObservationIgnored public var onOpenTab: ((any BrowserTab, NewTabDisposition) -> Void)?
    /// The page called `window.close()`.
    @ObservationIgnored public var onCloseRequest: (() -> Void)?

    public private(set) var tab: (any BrowserTab)?
    private var dialogs: [PendingDialog] = []

    /// Where each site's zoom level is kept, shared with the main windows.
    @ObservationIgnored public let zoomStore: PageZoomStore
    @ObservationIgnored private let permissions: SitePermissions
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var lastVisitedURL: URL?
    @ObservationIgnored private var reservedDestinations: Set<URL> = []
    @ObservationIgnored private var dialogAnswers: [UUID: CheckedContinuation<JavaScriptDialogResult, Never>] = [:]

    @ObservationIgnored private let engine: any BrowserEngine

    /// Opens `url`, or a blank page when it's nil, using `profile`'s website data.
    public init(engine: any BrowserEngine, url: URL?, profile: ProfileIdentifier = .default, archive: ArchiveStore? = nil,
                downloads: DownloadList? = nil, permissions: SitePermissions = SitePermissions(), zoomStore: PageZoomStore = PageZoomStore(),
                now: @escaping @MainActor () -> Date = { .now }) {
        self.engine = engine
        self.archive = archive
        self.downloads = downloads
        self.permissions = permissions
        self.zoomStore = zoomStore
        self.now = now
        let tab = engine.makeTab(url: url, profile: profile)
        self.tab = tab
        tab.delegate = self
        applyRememberedZoom(to: tab)
    }

    /// Opens the page again at its current address in another profile, for when its profile is deleted.
    public func switchProfile(to profile: ProfileIdentifier) {
        guard let old = tab, old.profile != profile else { return }
        dismissDialogs()
        old.delegate = nil
        old.close()
        let tab = engine.makeTab(url: old.state.url, profile: profile)
        self.tab = tab
        tab.delegate = self
        applyRememberedZoom(to: tab)
    }

    public var selectedTab: (any BrowserTab)? { tab }

    public var openTabs: [any BrowserTab] { tab.map { [$0] } ?? [] }

    public var dialogForSelectedTab: PendingDialog? { dialogs.first }

    /// Loads a typed address in the page.
    public func load(_ url: URL) {
        tab?.load(url)
    }

    /// Hands the live page over, for moving it to a main window, so it keeps its history. Waiting dialogs are
    /// dismissed. The model holds no page afterwards, and nothing goes to the archive.
    public func takeTab() -> (any BrowserTab)? {
        guard let tab else { return nil }
        self.tab = nil
        dismissDialogs()
        tab.delegate = nil
        return tab
    }

    /// Closes the page. A web page or file goes to the archive, so Reopen Archived Tab brings it back.
    public func close() {
        guard let tab else { return }
        self.tab = nil
        if let url = tab.state.url, ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
            archive?.add([ArchiveEntry(id: UUID(), url: url, title: tab.state.title, spaceID: nil, archivedAt: now())])
        }
        dismissDialogs()
        tab.delegate = nil
        tab.close()
    }

    // MARK: Dialogs

    public func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult) {
        dialogs.removeAll { $0.id == id }
        dialogAnswers.removeValue(forKey: id)?.resume(returning: result)
    }

    private func dismissDialogs() {
        for dialog in dialogs {
            dialogAnswers.removeValue(forKey: dialog.id)?.resume(returning: .dismissed)
        }
        dialogs.removeAll()
    }

    // MARK: BrowserTabDelegate

    public func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {
        if let onOpenTab {
            onOpenTab(newTab, disposition)
        } else {
            newTab.close()
        }
    }

    public func tabStateDidChange(_ tab: any BrowserTab) {
        guard tab === self.tab else { return }
        applyRememberedZoom(to: tab)
        let state = tab.state
        if !state.isLoading, let url = state.url, let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), lastVisitedURL != url {
            lastVisitedURL = url
            onPageVisited?(url, state.title)
        }
    }

    public func tabDidRequestClose(_ tab: any BrowserTab) {
        guard tab === self.tab else { return }
        onCloseRequest?()
    }

    public func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard tab === self.tab else { return .dismissed }
        let pending = PendingDialog(id: UUID(), tabID: tab.id, dialog: dialog)
        return await withCheckedContinuation { continuation in
            dialogAnswers[pending.id] = continuation
            dialogs.append(pending)
        }
    }

    public func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? {
        await onChooseFiles?(allowsMultiple, allowsDirectories)
    }

    public func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool {
        await permissions.decide(media, on: origin, ask: onCaptureRequest)
    }

    public func tab(_ tab: any BrowserTab, didStartDownload download: any BrowserDownload, suggestedFilename: String) async -> URL? {
        downloads?.add(download)
        guard let folder = downloadsFolder else { return nil }
        return reserveDownloadDestination(for: suggestedFilename, in: folder, downloads: downloads, reserved: &reservedDestinations)
    }
}
