import Archive
import Downloads
import BrowserEngine
import Foundation
import Observation
import Sidebar
import SidebarModel

/// One window's view of the shared sidebar: which space and tab it shows, the live pages behind
/// sidebar tabs, and the dialogs those pages are waiting on. Pages load when their tab is first selected.
@MainActor
@Observable
public final class BrowserWindowModel: BrowserTabDelegate {
    public let sidebar: SidebarStore
    /// Where closed unpinned tabs go. Nil keeps no archive.
    public let archive: ArchiveStore?
    /// Called once each time a tab finishes loading a new web address, with the title it has then.
    @ObservationIgnored public var onPageVisited: ((URL, String?) -> Void)?
    /// Asks the user for files to upload. Gets whether several files, and folders, are allowed. Nil means cancelled.
    @ObservationIgnored public var onChooseFiles: (@MainActor (Bool, Bool) async -> [URL]?)?
    /// Where a download goes, given its suggested name. Defaults to a free name in the Downloads folder.
    @ObservationIgnored public var onDownloadDestination: (@MainActor (String) -> URL?)?
    /// Asks the user whether a site may use the camera or microphone. Only called when there's no remembered choice.
    @ObservationIgnored public var onCaptureRequest: (@MainActor (MediaCapture, URL) async -> Bool)?
    /// Where downloads go when `onDownloadDestination` isn't set. Defaults to the user's Downloads folder.
    @ObservationIgnored public var downloadsFolder: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    /// This session's downloads, shared by every window.
    public let downloads: DownloadList?
    @ObservationIgnored private let permissions: SitePermissions
    @ObservationIgnored private var reservedDestinations: Set<URL> = []
    public private(set) var selectedSpaceID: SpaceID
    public private(set) var selectedItemID: ItemID?
    /// The page showing in Peek over the selected tab, or nil. A window has at most one.
    public private(set) var peekTab: (any BrowserTab)?
    private var liveTabs: [ItemID: any BrowserTab] = [:]
    /// Tabs put to sleep: their page is unloaded and this is where it wakes.
    private var snapshots: [ItemID: TabSnapshot] = [:]
    private var dialogs: [PendingDialog] = []

    @ObservationIgnored private let engine: any BrowserEngine
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var itemIDsByTab: [TabID: ItemID] = [:]
    /// Item to the item whose page opened it.
    @ObservationIgnored private var openerIDs: [ItemID: ItemID] = [:]
    @ObservationIgnored private var lastSelection: [SpaceID: ItemID] = [:]
    /// The tab whose link opened the current Peek.
    @ObservationIgnored private var peekSourceID: ItemID?
    @ObservationIgnored private var lastVisitedURLs: [TabID: URL] = [:]
    @ObservationIgnored private var dialogAnswers: [UUID: CheckedContinuation<JavaScriptDialogResult, Never>] = [:]

    /// Shows the first space, with its most recently active tab selected.
    public init(engine: any BrowserEngine, sidebar: SidebarStore, archive: ArchiveStore? = nil, downloads: DownloadList? = nil,
                permissions: SitePermissions = SitePermissions(), now: @escaping @MainActor () -> Date = { .now }) {
        self.engine = engine
        self.downloads = downloads
        self.permissions = permissions
        self.sidebar = sidebar
        self.archive = archive
        self.now = now
        selectedSpaceID = sidebar.document.spaces[0].id
        if let recent = mostRecentTab(in: selectedSpaceID) {
            setSelection(recent)
        }
    }

    private var document: SidebarDocument { sidebar.document }

    public var selectedTab: (any BrowserTab)? {
        selectedItemID.flatMap { liveTabs[$0] }
    }

    public func liveTab(for id: ItemID) -> (any BrowserTab)? {
        liveTabs[id]
    }

    /// The oldest dialog from the selected tab. Dialogs from other tabs wait until their tab is selected.
    public var dialogForSelectedTab: PendingDialog? {
        if let peekID = peekTab?.id, let dialog = dialogs.first(where: { $0.tabID == peekID }) {
            return dialog
        }
        guard let tabID = selectedTab?.id else { return nil }
        return dialogs.first { $0.tabID == tabID }
    }

    // MARK: Selecting

    /// Shows a tab, loading its page if it isn't live. Switches to the tab's space; favourites keep the current space.
    /// A split's ID selects the pane used most recently.
    public func select(_ id: ItemID) {
        let target = paneToShow(for: id) ?? id
        guard isTab(target) else { return }
        forgetOpenersUnlessRelated(to: target)
        setSelection(target)
    }

    public func selectSpace(_ id: SpaceID) {
        guard document.space(id) != nil, id != selectedSpaceID else { return }
        closePeek()
        openerIDs.removeAll()
        selectedSpaceID = id
        if let remembered = lastSelection[id], isTab(remembered), belongsToSelectedSpace(remembered) {
            setSelection(remembered)
        } else if let recent = mostRecentTab(in: id) {
            setSelection(recent)
        } else {
            leaveSelection()
        }
    }

    public func selectNextSpace() { selectSpace(offset: 1) }

    public func selectPreviousSpace() { selectSpace(offset: -1) }

    /// 1-based. Numbers past the last space do nothing.
    public func selectSpace(number: Int) {
        let spaces = document.spaces
        guard spaces.indices.contains(number - 1) else { return }
        selectSpace(spaces[number - 1].id)
    }

    public func selectNext() { selectTab(offset: 1) }

    public func selectPrevious() { selectTab(offset: -1) }

    /// 1 to 8 pick by position among favourites, pinned and unpinned tabs. 9 picks the last.
    public func select(number: Int) {
        let order = tabOrder()
        if number == 9, let last = order.last {
            select(last)
        } else if (1...8).contains(number), order.indices.contains(number - 1) {
            select(order[number - 1])
        }
    }

    // MARK: Tabs

    /// Adds a tab at the top of the current space's unpinned section and shows it.
    @discardableResult
    public func newTab(url: URL?) -> ItemID {
        let container = document.space(selectedSpaceID)!.unpinnedContainerID
        let id = sidebar.createTab(url: url, title: nil, in: container, at: 0)
        register(engine.makeTab(url: url), for: id)
        select(id)
        return id
    }

    /// Loads a typed address in the selected tab, or in a new tab when nothing is selected.
    public func load(_ url: URL) {
        if let tab = selectedTab {
            tab.load(url)
        } else {
            newTab(url: url)
        }
    }

    // MARK: Split view

    /// The split holding the selected tab, or nil when the selected tab isn't in one.
    public var selectedSplit: SplitLayout? {
        guard let selected = selectedItemID, let splitID = document.splitID(containing: selected),
              let split = document.item(splitID), case .split(let info) = split.kind
        else { return nil }
        return SplitLayout(id: splitID, paneIDs: split.childIDs, orientation: info.orientation, fractions: info.fractions)
    }

    /// Adds a blank tab beside the selected tab, making a split if there isn't one, and selects it.
    /// Nil when nothing is selected, a favourite is selected, or the split is full.
    @discardableResult
    public func addSplitPane() -> ItemID? {
        guard let selected = selectedItemID, document.containerRole(of: selected) != .favorites,
              (selectedSplit?.paneIDs.count ?? 1) < SidebarDocument.maximumSplitPanes
        else { return nil }
        let outer = document.splitID(containing: selected) ?? selected
        guard let container = document.item(outer)?.parentID,
              let index = document.item(container)?.childIDs.firstIndex(of: outer)
        else { return nil }
        let id = sidebar.createTab(url: nil, title: nil, in: container, at: index + 1)
        guard sidebar.addToSplit(id, with: selected) != nil else {
            sidebar.remove(id)
            return nil
        }
        register(engine.makeTab(url: nil), for: id)
        select(id)
        return id
    }

    /// True when tab `id` can go beside the selected tab: neither is a favourite, both are in the same section
    /// of the same space, so a pinned tab is never quietly unpinned, and the split has room.
    public func canOpenInSplit(_ id: ItemID) -> Bool {
        guard let selected = selectedItemID, selected != id, isTab(id),
              let role = document.containerRole(of: id), role != .favorites,
              document.containerRole(of: selected) == role
        else { return false }
        let panes = selectedSplit?.paneIDs ?? [selected]
        return !panes.contains(id) && panes.count < SidebarDocument.maximumSplitPanes
    }

    /// Shows an existing tab beside the selected tab and selects it.
    public func openInSplit(_ id: ItemID) {
        guard canOpenInSplit(id), let selected = selectedItemID, sidebar.addToSplit(id, with: selected) != nil else { return }
        select(id)
    }

    /// Turns the selected split back into separate tabs, keeping the selection.
    public func separateSelectedSplit() {
        guard let split = selectedSplit else { return }
        sidebar.separateSplit(split.id)
    }

    /// Switches the selected split between side by side and one above the other.
    public func rotateSelectedSplit() {
        guard let split = selectedSplit else { return }
        sidebar.setSplitOrientation(split.id, split.orientation == .horizontal ? .vertical : .horizontal)
    }

    public func resizeSelectedSplit(_ fractions: [Double]) {
        guard let split = selectedSplit else { return }
        sidebar.setSplitFractions(split.id, fractions)
    }

    /// Closes every pane. Unpinned panes go to the archive, as when closed one at a time.
    public func closeSplit(_ splitID: ItemID) {
        guard case .split = document.item(splitID)?.kind else { return }
        let panes = document.tabIDs(under: splitID)
        // Move the selection off the split first, so closing one pane never reloads another.
        if let selected = selectedItemID, panes.contains(selected) {
            let order = tabOrder()
            let after = order.drop { $0 != panes.last }.dropFirst().first
            let before = order.prefix { $0 != panes.first }.last
            if let next = after ?? before { setSelection(next) } else { leaveSelection() }
        }
        for pane in panes {
            close(pane)
        }
    }

    // MARK: Peek

    /// True when the Peek page can go in a split with the selected tab.
    public var canSplitPeek: Bool {
        guard peekTab != nil, let selected = selectedItemID, document.containerRole(of: selected) != .favorites else { return false }
        return (selectedSplit?.paneIDs.count ?? 1) < SidebarDocument.maximumSplitPanes
    }

    /// Closes the Peek page.
    public func closePeek() {
        guard let tab = peekTab else { return }
        peekTab = nil
        peekSourceID = nil
        dismissDialogs(of: tab)
        lastVisitedURLs[tab.id] = nil
        tab.delegate = nil
        tab.close()
    }

    /// Turns the Peek page into a tab at the top of the current space's unpinned tabs and selects it.
    /// The page stays live, so it doesn't reload.
    @discardableResult
    public func expandPeek() -> ItemID? {
        guard let tab = peekTab, let container = document.space(selectedSpaceID)?.unpinnedContainerID else { return nil }
        let source = peekSourceID
        peekTab = nil
        peekSourceID = nil
        let id = sidebar.createTab(url: tab.state.url, title: nil, in: container, at: 0)
        register(tab, for: id)
        if let source { openerIDs[id] = source }
        select(id)
        return id
    }

    /// Puts the Peek page in a split beside the selected tab. Only expands it when the selected tab can't be split.
    public func splitPeek() {
        let anchor = selectedItemID
        let canSplit = canSplitPeek
        guard let id = expandPeek() else { return }
        if canSplit, let anchor, sidebar.addToSplit(id, with: anchor) != nil {
            select(id)
        }
    }

    /// Opens `url` in Peek over the current page, replacing any Peek already open.
    private func openPeek(_ url: URL, from sourceID: ItemID) {
        closePeek()
        let tab = engine.makeTab(url: url)
        tab.delegate = self
        peekTab = tab
        peekSourceID = sourceID
    }

    private func isPeek(_ tab: any BrowserTab) -> Bool {
        peekTab?.id == tab.id
    }

    // MARK: Sleeping

    /// True while a tab's page is unloaded to save memory. Selecting it wakes it where it was.
    public func isSleeping(_ id: ItemID) -> Bool {
        snapshots[id] != nil
    }

    /// Unloads every page that may sleep and was last shown at least `interval` ago, keeping a snapshot to wake it from.
    /// Never sleeps what's on screen (the selected tab, its split's panes, Peek), or pages playing media,
    /// using the camera or microphone, or waiting on a dialog. An interval of 0 is for memory warnings.
    @discardableResult
    public func sleepTabs(unusedFor interval: TimeInterval) async -> [ItemID] {
        var slept: [ItemID] = []
        for id in liveTabs.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let tab = liveTabs[id], maySleep(id, unusedFor: interval) else { continue }
            if await tab.isPlayingMedia() { continue }
            if await tab.hasUnsavedState() { continue }
            // The selection may have moved while the page answered.
            guard liveTabs[id] === tab, maySleep(id, unusedFor: interval) else { continue }
            snapshots[id] = tab.snapshot()
            unload(id)
            slept.append(id)
        }
        return slept
    }

    private func maySleep(_ id: ItemID, unusedFor interval: TimeInterval) -> Bool {
        guard let tab = liveTabs[id], id != selectedItemID, selectedSplit?.paneIDs.contains(id) != true,
              !tab.state.isUsingCameraOrMicrophone, !dialogs.contains(where: { $0.tabID == tab.id })
        else { return false }
        let lastShown = tabInfo(id)?.lastActiveAt ?? document.item(id)?.createdAt ?? .distantPast
        return now().timeIntervalSince(lastShown) >= interval
    }

    /// The page a tab is on: its live page, or for a sleeping tab the page it will wake on. Nil when neither.
    public func currentPage(for id: ItemID) -> (url: URL?, title: String?)? {
        if let tab = liveTabs[id] { return (tab.state.url, tab.state.title) }
        return snapshots[id].map { ($0.url, $0.title) }
    }

    /// `currentPage` with the title the sidebar shows, for rows, tiles and the command bar.
    public func pageForDisplay(for id: ItemID) -> (url: URL?, title: String)? {
        if let tab = liveTabs[id] { return (tab.state.url, displayTitle(for: tab.state)) }
        return snapshots[id].map { snapshot in
            (snapshot.url, displayTitle(for: TabState(url: snapshot.url, title: snapshot.title, isLoading: false, estimatedProgress: 1, canGoBack: false, canGoForward: false)))
        }
    }

    /// A new page for a tab: woken from its snapshot when it was asleep, otherwise loading its saved address.
    private func makePage(for id: ItemID) -> any BrowserTab {
        if let snapshot = snapshots.removeValue(forKey: id) {
            return engine.makeTab(restoring: snapshot)
        }
        return engine.makeTab(url: tabInfo(id)?.savedURL)
    }

    // MARK: Closing

    /// Unpinned tabs are removed from the sidebar. Pinned tabs and favourites stay and only unload their page.
    public func close(_ id: ItemID) {
        let isUnpinned: Bool
        if case .unpinned = document.containerRole(of: id) { isUnpinned = true } else { isUnpinned = false }
        close(id, removing: isUnpinned)
    }

    /// Removes any tab from the sidebar, pinned tabs and favourites included. It goes to the archive, so it can be reopened.
    public func delete(_ id: ItemID) {
        guard isTab(id) else { return }
        close(id, removing: true)
    }

    private func close(_ id: ItemID, removing: Bool) {
        let next = selectedItemID == id ? selectionAfterClosing(id) : selectedItemID
        // A closed pane leaves its split first, so a pinned pane doesn't stay in the split and load again.
        if let splitID = document.splitID(containing: id), let parent = document.item(splitID)?.parentID,
           let index = document.item(parent)?.childIDs.firstIndex(of: splitID) {
            try? sidebar.move(id, to: parent, at: index + 1)
        }
        if removing {
            archive?.add(archiveEntries(for: [id]))
        }
        unload(id)
        snapshots[id] = nil
        if removing {
            sidebar.remove(id)
        }
        forgetOpener(id)
        if selectedItemID == id {
            if let next { setSelection(next) } else { leaveSelection() }
        }
    }

    public func resetToSavedURL(_ id: ItemID) {
        guard let saved = tabInfo(id)?.savedURL else { return }
        if let tab = liveTabs[id] {
            tab.load(saved)
        } else {
            // A sleeping tab wakes on its saved address, not where it was.
            snapshots[id] = nil
            select(id)
        }
    }

    /// True when a pinned tab or favourite has navigated away from its saved address.
    public func isAwayFromSavedURL(_ id: ItemID) -> Bool {
        switch document.containerRole(of: id) {
        case .pinned, .favorites: break
        default: return false
        }
        guard let saved = tabInfo(id)?.savedURL, let current = currentPage(for: id)?.url else { return false }
        return !sameAddress(saved, current)
    }

    /// Pins an unpinned tab, unpins a pinned one, and moves a favourite to the current space's unpinned tabs.
    public func togglePin(_ id: ItemID) {
        switch document.containerRole(of: id) {
        case .unpinned(let space): sidebar.pin(id, in: space)
        case .pinned(let space): sidebar.unpin(id, in: space)
        case .favorites: sidebar.unpin(id, in: selectedSpaceID)
        case nil: break
        }
    }

    /// Closes every unpinned tab in the current space.
    public func clearUnpinned() {
        guard let container = document.space(selectedSpaceID)?.unpinnedContainerID else { return }
        let ids = document.tabIDs(under: container)
        let selectionCleared = selectedItemID.map { document.containerRole(of: $0) == .unpinned(selectedSpaceID) } ?? false
        archive?.add(archiveEntries(for: ids))
        for id in ids {
            unload(id)
            snapshots[id] = nil
            forgetOpener(id)
        }
        sidebar.clearUnpinned(in: selectedSpaceID)
        if selectionCleared {
            if let recent = mostRecentTab(in: selectedSpaceID) { setSelection(recent) } else { leaveSelection() }
        }
    }

    /// Brings an archived tab back at the top of its space's unpinned tabs, or the current space's
    /// if its space is gone, and shows it.
    public func restore(_ entryID: UUID) {
        guard let entry = archive?.remove(entryID) else { return }
        let spaceID = entry.spaceID.flatMap { document.space($0)?.id } ?? selectedSpaceID
        guard let container = document.space(spaceID)?.unpinnedContainerID else { return }
        let id = sidebar.createTab(url: entry.url, title: entry.title, in: container, at: 0)
        register(engine.makeTab(url: entry.url), for: id)
        select(id)
    }

    /// Restores the tab the user closed most recently. Skips tabs Sela archived for inactivity,
    /// so a sweep in the background doesn't change what Reopen brings back. Does nothing when there's none.
    public func reopenLastArchived() {
        guard let newest = archive?.entries.first(where: { $0.reason == .closed }) else { return }
        restore(newest.id)
    }

    /// Drops live pages and selections whose sidebar items or spaces no longer exist,
    /// for example after another window closed a tab.
    public func reconcile() {
        for id in Array(snapshots.keys) where !isTab(id) {
            snapshots[id] = nil
        }
        for id in Array(liveTabs.keys) where !isTab(id) {
            unload(id)
            forgetOpener(id)
        }
        if document.space(selectedSpaceID) == nil {
            selectedSpaceID = document.spaces[0].id
            if let recent = mostRecentTab(in: selectedSpaceID) { setSelection(recent) } else { leaveSelection() }
        } else if let selected = selectedItemID, !isTab(selected) || !belongsToSelectedSpace(selected) {
            if let recent = mostRecentTab(in: selectedSpaceID) { setSelection(recent) } else { leaveSelection() }
        }
    }

    /// Records that the selected tab is in use right now, for example when Sela quits,
    /// so archiving counts from now rather than from when it was selected.
    public func markSelectionActive() {
        if let selected = selectedItemID {
            sidebar.markActive(selected, at: now())
        }
    }

    /// Closes every live page, for when the window closes.
    public func closeAllLiveTabs() {
        closePeek()
        for id in Array(liveTabs.keys) { unload(id) }
        snapshots.removeAll()
        openerIDs.removeAll()
        leaveSelection()
    }

    // MARK: Dialogs

    public func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult) {
        dialogs.removeAll { $0.id == id }
        dialogAnswers.removeValue(forKey: id)?.resume(returning: result)
    }

    // MARK: BrowserTabDelegate

    public func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {
        // Pages opened from Peek belong to the tab whose link opened the Peek.
        let sourceID = itemIDsByTab[tab.id] ?? (isPeek(tab) ? peekSourceID : nil)
        let spaceID = sourceID.flatMap(document.spaceID(containing:)) ?? selectedSpaceID
        guard let container = document.space(spaceID)?.unpinnedContainerID else { return }

        // After the source when it's unpinned, otherwise at the top, then after tabs the source already opened.
        let siblings = document.item(container)?.childIDs ?? []
        var position = sourceID.flatMap { siblings.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        while let sourceID, siblings.indices.contains(position), openerIDs[siblings[position]] == sourceID {
            position += 1
        }

        let id = sidebar.createTab(url: newTab.state.url, title: nil, in: container, at: position)
        register(newTab, for: id)
        if let sourceID { openerIDs[id] = sourceID }
        if disposition == .foreground {
            setSelection(id)
        }
    }

    public func tabStateDidChange(_ tab: any BrowserTab) {
        let state = tab.state
        if let id = itemIDsByTab[tab.id] {
            sidebar.recordPage(id, url: state.url, title: state.title)
        } else if !isPeek(tab) {
            return
        }
        if !state.isLoading, let url = state.url, let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), lastVisitedURLs[tab.id] != url {
            lastVisitedURLs[tab.id] = url
            onPageVisited?(url, state.title)
        }
    }

    public func tabDidRequestClose(_ tab: any BrowserTab) {
        if isPeek(tab) {
            closePeek()
            return
        }
        guard let id = itemIDsByTab[tab.id] else { return }
        close(id)
    }

    public func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard itemIDsByTab[tab.id] != nil || isPeek(tab) else { return .dismissed }
        let pending = PendingDialog(id: UUID(), tabID: tab.id, dialog: dialog)
        return await withCheckedContinuation { continuation in
            dialogAnswers[pending.id] = continuation
            dialogs.append(pending)
        }
    }

    public func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? {
        await onChooseFiles?(allowsMultiple, allowsDirectories)
    }

    /// Uses the remembered choice for the site, or asks and remembers the answer.
    public func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool {
        if let decision = permissions.decision(for: media, on: origin) { return decision }
        guard let onCaptureRequest else { return false }
        let allowed = await onCaptureRequest(media, origin)
        permissions.remember(allowed, for: media, on: origin)
        return allowed
    }

    public func tab(_ tab: any BrowserTab, didStartDownload download: any BrowserDownload, suggestedFilename: String) async -> URL? {
        downloads?.add(download)
        if let onDownloadDestination { return onDownloadDestination(suggestedFilename) }
        guard let folder = downloadsFolder else { return nil }
        // Taken means on disk, half-written, or promised to another download that hasn't written yet.
        let destination = availableDestination(for: suggestedFilename, in: folder) { [downloads, reservedDestinations] url in
            FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: partialURL(for: url).path)
                || downloads?.isReserved(url) == true || reservedDestinations.contains(url.standardizedFileURL)
        }
        downloads?.reserve(destination)
        reservedDestinations.insert(destination.standardizedFileURL)
        return destination
    }

    /// Links from pinned tabs and favourites to another site open in Peek, and so does a Shift-click in any tab.
    public func tab(_ tab: any BrowserTab, shouldFollowLinkTo url: URL, shiftKey: Bool) -> Bool {
        guard let sourceID = itemIDsByTab[tab.id] else { return true }
        let isKept: Bool
        switch document.containerRole(of: sourceID) {
        case .pinned, .favorites: isKept = true
        default: isKept = false
        }
        let current = tab.state.url ?? tabInfo(sourceID)?.savedURL
        let leavesSite = siteKey(forHost: url.host() ?? "") != siteKey(forHost: current?.host() ?? "")
        guard shiftKey || (isKept && leavesSite) else { return true }
        openPeek(url, from: sourceID)
        return false
    }

    // MARK: Helpers

    /// Selects without touching opener links. Creates the live page if needed and records activity.
    private func setSelection(_ id: ItemID) {
        closePeek()
        if let spaceID = document.spaceID(containing: id), spaceID != selectedSpaceID {
            selectedSpaceID = spaceID
        }
        // Every pane of a split shows at once, so every pane needs its page.
        let panes = document.splitID(containing: id).map { document.tabIDs(under: $0) } ?? [id]
        for pane in panes where liveTabs[pane] == nil {
            register(makePage(for: pane), for: pane)
        }
        let date = now()
        if let previous = selectedItemID, previous != id {
            sidebar.markActive(previous, at: date)
        }
        sidebar.markActive(id, at: date)
        selectedItemID = id
        lastSelection[selectedSpaceID] = id
    }

    private func leaveSelection() {
        if let previous = selectedItemID {
            sidebar.markActive(previous, at: now())
        }
        selectedItemID = nil
        lastSelection[selectedSpaceID] = nil
    }

    private func register(_ tab: any BrowserTab, for id: ItemID) {
        tab.delegate = self
        liveTabs[id] = tab
        itemIDsByTab[tab.id] = id
    }

    /// Closes an item's live page, answering its dialogs as dismissed.
    private func unload(_ id: ItemID) {
        guard let tab = liveTabs.removeValue(forKey: id) else { return }
        itemIDsByTab[tab.id] = nil
        lastVisitedURLs[tab.id] = nil
        dismissDialogs(of: tab)
        tab.delegate = nil
        tab.close()
    }

    /// Answers a page's waiting dialogs as dismissed.
    private func dismissDialogs(of tab: any BrowserTab) {
        for dialog in dialogs where dialog.tabID == tab.id {
            dialogAnswers.removeValue(forKey: dialog.id)?.resume(returning: .dismissed)
        }
        dialogs.removeAll { $0.tabID == tab.id }
    }

    private func forgetOpener(_ id: ItemID) {
        openerIDs[id] = nil
        openerIDs = openerIDs.filter { $0.value != id }
    }

    /// Moving to a tab outside the current tab's family (its opener, its children, or tabs with the same opener)
    /// forgets every opener link, so closing a tab later doesn't jump back to a page the user has moved on from.
    private func forgetOpenersUnlessRelated(to id: ItemID) {
        guard let current = selectedItemID, current != id else { return }
        let currentOpener = openerIDs[current]
        let newOpener = openerIDs[id]
        let related = id == currentOpener || newOpener == current || (newOpener != nil && newOpener == currentOpener)
        if !related { openerIDs.removeAll() }
    }

    /// Archive entries for tabs about to leave the sidebar, using the live page's address and title when there is one.
    private func archiveEntries(for ids: [ItemID]) -> [ArchiveEntry] {
        let date = now()
        return ids.compactMap { id in
            guard var entry = archiveEntry(for: id, in: document, at: date) else { return nil }
            if let state = liveTabs[id]?.state, let url = state.url {
                entry.url = url
                entry.title = document.item(id)?.title ?? state.title ?? entry.title
            }
            return entry
        }
    }

    /// The next sibling with the same opener, then the opener, then the tab below, then the tab above.
    private func selectionAfterClosing(_ id: ItemID) -> ItemID? {
        if let splitID = document.splitID(containing: id) {
            let panes = document.tabIDs(under: splitID)
            if let index = panes.firstIndex(of: id), panes.count > 1 {
                return panes.indices.contains(index + 1) ? panes[index + 1] : panes[index - 1]
            }
        }
        let order = tabOrder()
        guard let index = order.firstIndex(of: id) else { return mostRecentTab(in: selectedSpaceID, excluding: id) }
        if let opener = openerIDs[id] {
            if let sibling = order[(index + 1)...].first(where: { openerIDs[$0] == opener }) { return sibling }
            if isTab(opener) { return opener }
        }
        if order.indices.contains(index + 1) { return order[index + 1] }
        if index > 0 { return order[index - 1] }
        return nil
    }

    /// Favourites, then the current space's pinned tabs depth-first, then its unpinned tabs.
    private func tabOrder() -> [ItemID] {
        guard let space = document.space(selectedSpaceID) else { return [] }
        return document.tabIDs(under: document.favoritesContainerID)
            + document.tabIDs(under: space.pinnedContainerID)
            + document.tabIDs(under: space.unpinnedContainerID)
    }

    private func selectTab(offset: Int) {
        let order = tabOrder()
        guard !order.isEmpty else { return }
        let current = selectedItemID.flatMap { order.firstIndex(of: $0) } ?? (offset > 0 ? -1 : 0)
        select(order[(current + offset + order.count) % order.count])
    }

    private func selectSpace(offset: Int) {
        let spaces = document.spaces
        guard let current = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        selectSpace(spaces[(current + offset + spaces.count) % spaces.count].id)
    }

    /// The space's pinned or unpinned tab that was active most recently. Nil when none has been active.
    private func mostRecentTab(in spaceID: SpaceID, excluding excluded: ItemID? = nil) -> ItemID? {
        guard let space = document.space(spaceID) else { return nil }
        let candidates = document.tabIDs(under: space.pinnedContainerID) + document.tabIDs(under: space.unpinnedContainerID)
        return candidates
            .filter { $0 != excluded }
            .compactMap { id in tabInfo(id)?.lastActiveAt.map { (id, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func belongsToSelectedSpace(_ id: ItemID) -> Bool {
        let space = document.spaceID(containing: id)
        return space == nil || space == selectedSpaceID
    }

    /// For a split, its pane used most recently, or its first pane when none has been used.
    private func paneToShow(for id: ItemID) -> ItemID? {
        guard case .split = document.item(id)?.kind else { return nil }
        let panes = document.tabIDs(under: id)
        let recent = panes.compactMap { pane in tabInfo(pane)?.lastActiveAt.map { (pane, $0) } }.max { $0.1 < $1.1 }
        return recent?.0 ?? panes.first
    }

    private func isTab(_ id: ItemID) -> Bool {
        tabInfo(id) != nil
    }

    private func tabInfo(_ id: ItemID) -> TabInfo? {
        if case .tab(let info) = document.item(id)?.kind { return info }
        return nil
    }
}

/// Treats addresses that differ only by scheme case, host case, a leading `www.` or a trailing slash as the same.
func sameAddress(_ a: URL, _ b: URL) -> Bool {
    func normalized(_ url: URL) -> String {
        var host = url.host()?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        let query = url.query().map { "?\($0)" } ?? ""
        return "\(url.scheme?.lowercased() ?? "")://\(host)\(path)\(query)"
    }
    return normalized(a) == normalized(b)
}
