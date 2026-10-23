import BrowserEngine
import Foundation
import Observation

/// The tabs in one window, which one is selected, and the dialogs pages are waiting on.
@MainActor
@Observable
public final class BrowserWindowModel: BrowserTabDelegate {
    public private(set) var tabs: [any BrowserTab] = []
    public private(set) var selectedTabID: TabID?
    private var dialogs: [PendingDialog] = []

    @ObservationIgnored private let engine: any BrowserEngine
    /// Tab to the tab that opened it.
    @ObservationIgnored private var openerIDs: [TabID: TabID] = [:]
    @ObservationIgnored private var dialogAnswers: [UUID: CheckedContinuation<JavaScriptDialogResult, Never>] = [:]

    public init(engine: any BrowserEngine) {
        self.engine = engine
    }

    public var selectedTab: (any BrowserTab)? {
        tabs.first { $0.id == selectedTabID }
    }

    /// The oldest dialog from the selected tab. Dialogs from other tabs wait until their tab is selected.
    public var dialogForSelectedTab: PendingDialog? {
        dialogs.first { $0.tabID == selectedTabID }
    }

    // MARK: Tabs

    /// Adds a tab at the end.
    @discardableResult
    public func openTab(url: URL?, select: Bool = true) -> any BrowserTab {
        let tab = engine.makeTab(url: url)
        insert(tab, at: tabs.endIndex, select: select)
        return tab
    }

    public func select(_ id: TabID) {
        guard index(of: id) != nil else { return }
        selectedTabID = id
    }

    /// Closes a tab. When it was selected, selects its opener, else the tab below, else the tab above.
    public func close(_ id: TabID) {
        guard let index = index(of: id) else { return }
        let tab = tabs.remove(at: index)
        let openerID = openerIDs.removeValue(forKey: id)
        openerIDs = openerIDs.filter { $0.value != id }

        for dialog in dialogs where dialog.tabID == id {
            dialogAnswers.removeValue(forKey: dialog.id)?.resume(returning: .dismissed)
        }
        dialogs.removeAll { $0.tabID == id }

        if selectedTabID == id {
            if let openerID, self.index(of: openerID) != nil {
                selectedTabID = openerID
            } else if tabs.indices.contains(index) {
                selectedTabID = tabs[index].id
            } else {
                selectedTabID = tabs.last?.id
            }
        }
        tab.delegate = nil
        tab.close()
    }

    public func selectNext() { selectRelative(1) }

    public func selectPrevious() { selectRelative(-1) }

    /// 1 to 8 select by position. 9 selects the last tab.
    public func select(number: Int) {
        if number == 9, let last = tabs.last {
            selectedTabID = last.id
        } else if (1...8).contains(number), tabs.indices.contains(number - 1) {
            selectedTabID = tabs[number - 1].id
        }
    }

    // MARK: Dialogs

    public func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult) {
        dialogs.removeAll { $0.id == id }
        dialogAnswers.removeValue(forKey: id)?.resume(returning: result)
    }

    // MARK: BrowserTabDelegate

    public func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {
        guard var position = index(of: tab.id) else {
            insert(newTab, at: tabs.endIndex, select: disposition == .foreground)
            return
        }
        position += 1
        while tabs.indices.contains(position), openerIDs[tabs[position].id] == tab.id {
            position += 1
        }
        openerIDs[newTab.id] = tab.id
        insert(newTab, at: position, select: disposition == .foreground)
    }

    public func tabDidRequestClose(_ tab: any BrowserTab) {
        close(tab.id)
    }

    public func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard index(of: tab.id) != nil else { return .dismissed }
        let pending = PendingDialog(id: UUID(), tabID: tab.id, dialog: dialog)
        return await withCheckedContinuation { continuation in
            dialogAnswers[pending.id] = continuation
            dialogs.append(pending)
        }
    }

    // MARK: Helpers

    private func insert(_ tab: any BrowserTab, at position: Int, select: Bool) {
        tab.delegate = self
        tabs.insert(tab, at: position)
        if select || selectedTabID == nil {
            selectedTabID = tab.id
        }
    }

    private func index(of id: TabID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    private func selectRelative(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = selectedTabID.flatMap(index(of:)) ?? 0
        let next = (current + offset + tabs.count) % tabs.count
        selectedTabID = tabs[next].id
    }
}
