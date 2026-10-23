import Archive
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
    public private(set) var selectedSpaceID: SpaceID
    public private(set) var selectedItemID: ItemID?
    private var liveTabs: [ItemID: any BrowserTab] = [:]
    private var dialogs: [PendingDialog] = []

    @ObservationIgnored private let engine: any BrowserEngine
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var itemIDsByTab: [TabID: ItemID] = [:]
    /// Item to the item whose page opened it.
    @ObservationIgnored private var openerIDs: [ItemID: ItemID] = [:]
    @ObservationIgnored private var lastSelection: [SpaceID: ItemID] = [:]
    @ObservationIgnored private var lastVisitedURLs: [TabID: URL] = [:]
    @ObservationIgnored private var dialogAnswers: [UUID: CheckedContinuation<JavaScriptDialogResult, Never>] = [:]

    /// Shows the first space, with its most recently active tab selected.
    public init(engine: any BrowserEngine, sidebar: SidebarStore, archive: ArchiveStore? = nil, now: @escaping @MainActor () -> Date = { .now }) {
        self.engine = engine
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
        guard let tabID = selectedTab?.id else { return nil }
        return dialogs.first { $0.tabID == tabID }
    }

    // MARK: Selecting

    /// Shows a tab, loading its page if it isn't live. Switches to the tab's space; favourites keep the current space.
    public func select(_ id: ItemID) {
        guard isTab(id) else { return }
        forgetOpenersUnlessRelated(to: id)
        setSelection(id)
    }

    public func selectSpace(_ id: SpaceID) {
        guard document.space(id) != nil, id != selectedSpaceID else { return }
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

    /// Unpinned tabs are removed from the sidebar. Pinned tabs and favourites stay and only unload their page.
    public func close(_ id: ItemID) {
        let next = selectedItemID == id ? selectionAfterClosing(id) : selectedItemID
        let isUnpinned: Bool
        if case .unpinned = document.containerRole(of: id) { isUnpinned = true } else { isUnpinned = false }
        if isUnpinned {
            archive?.add(archiveEntries(for: [id]))
        }
        unload(id)
        if isUnpinned {
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
            select(id)
        }
    }

    /// True when a pinned tab or favourite has navigated away from its saved address.
    public func isAwayFromSavedURL(_ id: ItemID) -> Bool {
        switch document.containerRole(of: id) {
        case .pinned, .favorites: break
        default: return false
        }
        guard let saved = tabInfo(id)?.savedURL, let current = liveTabs[id]?.state.url else { return false }
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

    /// Restores the most recently archived tab. Does nothing when the archive is empty.
    public func reopenLastArchived() {
        guard let newest = archive?.entries.first else { return }
        restore(newest.id)
    }

    /// Drops live pages and selections whose sidebar items or spaces no longer exist,
    /// for example after another window closed a tab.
    public func reconcile() {
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

    /// Closes every live page, for when the window closes.
    public func closeAllLiveTabs() {
        for id in Array(liveTabs.keys) { unload(id) }
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
        let sourceID = itemIDsByTab[tab.id]
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
        guard let id = itemIDsByTab[tab.id] else { return }
        let state = tab.state
        sidebar.recordPage(id, url: state.url, title: state.title)
        if !state.isLoading, let url = state.url, let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), lastVisitedURLs[tab.id] != url {
            lastVisitedURLs[tab.id] = url
            onPageVisited?(url, state.title)
        }
    }

    public func tabDidRequestClose(_ tab: any BrowserTab) {
        guard let id = itemIDsByTab[tab.id] else { return }
        close(id)
    }

    public func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard itemIDsByTab[tab.id] != nil else { return .dismissed }
        let pending = PendingDialog(id: UUID(), tabID: tab.id, dialog: dialog)
        return await withCheckedContinuation { continuation in
            dialogAnswers[pending.id] = continuation
            dialogs.append(pending)
        }
    }

    // MARK: Helpers

    /// Selects without touching opener links. Creates the live page if needed and records activity.
    private func setSelection(_ id: ItemID) {
        if let spaceID = document.spaceID(containing: id), spaceID != selectedSpaceID {
            selectedSpaceID = spaceID
        }
        if liveTabs[id] == nil {
            register(engine.makeTab(url: tabInfo(id)?.savedURL), for: id)
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
        for dialog in dialogs where dialog.tabID == tab.id {
            dialogAnswers.removeValue(forKey: dialog.id)?.resume(returning: .dismissed)
        }
        dialogs.removeAll { $0.tabID == tab.id }
        tab.delegate = nil
        tab.close()
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
