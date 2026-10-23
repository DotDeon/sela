import AppKit
import Archive
import Browsing
import CommandBar
import Favicons
import History
import SidebarModel
import SidebarUI

/// Shows the command bar over one window and carries out what's chosen.
@MainActor
final class CommandBarPresenter {
    private let model: BrowserWindowModel
    private let history: HistoryStore?
    private let favicons: FaviconStore
    private let runCommand: (String) -> Void
    private weak var host: NSView?
    private var backdrop: NSView?
    private var panel: CommandBarViewController?
    /// What had keyboard focus before the bar opened, given back when it closes without an action.
    private weak var previousResponder: NSResponder?

    static let commands = [
        CommandCandidate(id: "new-space", title: "New Space", keywords: ["create"]),
        CommandCandidate(id: "toggle-sidebar", title: "Toggle Sidebar", keywords: ["hide", "show"]),
        CommandCandidate(id: "copy-url", title: "Copy URL", keywords: ["link", "address"]),
        CommandCandidate(id: "pin-tab", title: "Pin or Unpin Tab", keywords: []),
        CommandCandidate(id: "clear-unpinned", title: "Clear Unpinned Tabs", keywords: ["close", "archive"]),
        CommandCandidate(id: "reopen-archived", title: "Reopen Last Archived Tab", keywords: ["undo", "restore"]),
        CommandCandidate(id: "clear-history", title: "Clear History…", keywords: ["delete", "privacy"]),
        CommandCandidate(id: "new-window", title: "New Window", keywords: []),
    ]

    init(model: BrowserWindowModel, history: HistoryStore?, favicons: FaviconStore, host: NSView, runCommand: @escaping (String) -> Void) {
        self.model = model
        self.history = history
        self.favicons = favicons
        self.host = host
        self.runCommand = runCommand
    }

    var isShowing: Bool { panel != nil }

    func show(_ mode: CommandBarMode) {
        if panel == nil {
            previousResponder = host?.window?.firstResponder
        }
        removePanel()
        guard let host else { return }
        let barModel = CommandBarModel(mode: mode, sources: sources())
        let controller = CommandBarViewController(
            model: barModel,
            icon: { [weak self] in self?.icon(for: $0) },
            onAction: { [weak self] in self?.perform($0) },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let shade = Backdrop()
        shade.onClick = { [weak self] in self?.dismiss() }
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        shade.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(shade)
        let panelView = controller.view
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.shadow = NSShadow()
        shade.addSubview(panelView)
        NSLayoutConstraint.activate([
            shade.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            shade.topAnchor.constraint(equalTo: host.topAnchor),
            shade.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            panelView.centerXAnchor.constraint(equalTo: shade.centerXAnchor),
            panelView.topAnchor.constraint(equalTo: shade.topAnchor, constant: 120),
        ])
        backdrop = shade
        panel = controller
        controller.focus()
    }

    /// Closes the bar and gives keyboard focus back to what had it.
    func dismiss() {
        let window = host?.window
        removePanel()
        if let previousResponder, let window {
            window.makeFirstResponder(previousResponder)
        }
    }

    private func removePanel() {
        backdrop?.removeFromSuperview()
        backdrop = nil
        panel = nil
    }

    // MARK: Results

    private func sources() -> CommandBarSources {
        CommandBarSources(
            tabs: { [model] in Self.tabCandidates(model) },
            commands: Self.commands,
            archived: { [model] query in
                (model.archive?.search(query) ?? []).map {
                    ArchivedCandidate(id: $0.id, title: $0.title ?? $0.url?.host() ?? "Archived Tab", url: $0.url)
                }
            },
            history: { [history] query in
                (history?.search(query, limit: 20) ?? []).map {
                    HistoryCandidate(url: $0.url, title: $0.title ?? $0.url.host() ?? $0.url.absoluteString)
                }
            }
        )
    }

    private static func tabCandidates(_ model: BrowserWindowModel) -> [TabCandidate] {
        let document = model.sidebar.document
        let containers = [document.favoritesContainerID] + document.spaces.flatMap { [$0.pinnedContainerID, $0.unpinnedContainerID] }
        return containers.flatMap { document.tabIDs(under: $0) }.compactMap { id in
            guard let item = document.item(id), case .tab(let info) = item.kind else { return nil }
            let state = model.liveTab(for: id)?.state
            let title = sidebarTitle(for: item, liveState: state.map { ($0.url, displayTitle(for: $0)) })
            return TabCandidate(id: id, title: title, url: state?.url ?? info.savedURL, lastActiveAt: info.lastActiveAt)
        }
    }

    private func icon(for result: CommandBarResult) -> NSImage? {
        switch result {
        case .tab(let tab): favicons.image(forPage: tab.url)
        case .archived(let entry): favicons.image(forPage: entry.url)
        case .history(let page): favicons.image(forPage: page.url)
        case .open, .command: nil
        }
    }

    private func perform(_ action: CommandBarAction) {
        removePanel()
        switch action {
        case .open(let url, let inNewTab):
            if inNewTab { model.newTab(url: url) } else { model.load(url) }
        case .selectTab(let id):
            model.select(id)
        case .restoreArchived(let id):
            model.restore(id)
        case .runCommand(let id):
            runCommand(id)
        }
        // The page view is swapped in on the next pass of the main queue, so focus it after that.
        DispatchQueue.main.async { [weak self] in
            guard let self, let content = self.model.selectedTab?.contentView, let window = content.window else {
                if let previous = self?.previousResponder { self?.host?.window?.makeFirstResponder(previous) }
                return
            }
            window.makeFirstResponder(content)
        }
    }
}

/// The dimmed area behind the command bar. A click on it closes the bar.
private final class Backdrop: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
