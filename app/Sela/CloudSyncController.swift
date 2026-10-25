import AppKit
import CloudSync
import RemoteSettings
import Sidebar
import SidebarUI

/// Runs iCloud sync in a copy of Sela signed for it, and shows the two things the person has to see: the
/// question when a merge would take away most of the sidebar, and a banner when sync pauses.
@MainActor
final class CloudSyncController {
    let model: CloudSyncModel
    private let bannerHost: () -> NSView?
    private var shownProblem: SyncProblem?
    private var isAsking = false
    private var activeObserver: (any NSObjectProtocol)?

    /// Nil without the iCloud entitlements, so nothing touches CloudKit and Settings has no Sync tab.
    init?(sidebar: SidebarStore, ledgerFile: URL, bannerHost: @escaping () -> NSView?) {
        guard CloudSyncEntitlement.isPresent else { return nil }
        model = CloudSyncModel(sidebar: sidebar, transport: CloudKitTransport(), ledgerStore: SyncLedgerStore(fileURL: ledgerFile))
        self.bannerHost = bannerHost
    }

    func start() {
        keepObserving { [weak self] in
            guard let self, model.pendingRemoval != nil, !isAsking else { return }
            isAsking = true
            Task { @MainActor [weak self] in self?.askAboutRemoval() }
        }
        keepObserving { [weak self] in
            guard let self else { return }
            let problem = model.problem
            guard problem?.pausesSync == true, problem != shownProblem else { return }
            shownProblem = problem
            Task { @MainActor [weak self] in self?.showBanner(problem!) }
        }
        // The sync engine listens for iCloud's silent pushes once the app is registered for them.
        keepObserving { [weak self] in
            guard let self, model.isEnabled else { return }
            NSApp.registerForRemoteNotifications()
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.model.refreshAccountStatus() }
        }
    }

    /// iCloud's sidebar is missing most of what this Mac has. Keeping this Mac's items sends them back up.
    private func askAboutRemoval() {
        defer { isAsking = false }
        guard let pending = model.pendingRemoval else { return }
        let alert = NSAlert()
        alert.messageText = "iCloud would remove most of your sidebar"
        alert.informativeText = "The sidebar in iCloud is missing \(pending.removedItems) of the \(pending.localItems) pinned tabs, folders and favourites on this Mac. That happens when another Mac's sidebar was emptied or iCloud's copy is damaged. Keeping them sends them back to iCloud and your other Macs."
        alert.addButton(withTitle: "Keep This Mac's Sidebar")
        alert.addButton(withTitle: "Remove Them")
        alert.buttons.last?.hasDestructiveAction = true
        let response = alert.runModal()
        model.resolvePendingRemoval(applying: response == .alertSecondButtonReturn)
    }

    private func showBanner(_ problem: SyncProblem) {
        guard let host = bannerHost(), let message = RemoteMessage(id: "cloud-sync", text: problem.text) else { return }
        MessageBanner.show(message, in: host) { _ in }
    }
}
