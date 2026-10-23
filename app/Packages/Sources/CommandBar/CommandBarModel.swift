import Foundation
import Observation
import SidebarModel

/// What the command bar was opened for.
public enum CommandBarMode: Equatable, Sendable {
    /// Cmd+T: addresses and searches open in a new tab.
    case newTab
    /// Cmd+L: starts with the current address; addresses and searches load in the current tab.
    case currentTab(address: String)
}

/// What the window should do with the chosen row.
public enum CommandBarAction: Equatable, Sendable {
    case open(URL, inNewTab: Bool)
    case selectTab(ItemID)
    case runCommand(String)
    case restoreArchived(UUID)
}

/// Where the command bar's candidates come from. Archived and history lookups get the query.
public struct CommandBarSources {
    public var tabs: () -> [TabCandidate]
    public var commands: [CommandCandidate]
    public var archived: (String) -> [ArchivedCandidate]
    public var history: (String) -> [HistoryCandidate]

    public init(tabs: @escaping () -> [TabCandidate], commands: [CommandCandidate], archived: @escaping (String) -> [ArchivedCandidate], history: @escaping (String) -> [HistoryCandidate]) {
        self.tabs = tabs
        self.commands = commands
        self.archived = archived
        self.history = history
    }
}

/// The command bar's text, results and selected row.
@MainActor
@Observable
public final class CommandBarModel {
    public let mode: CommandBarMode
    public var query: String {
        didSet { refresh() }
    }
    public private(set) var results: [CommandBarResult] = []
    public private(set) var selectedIndex = 0

    @ObservationIgnored private let sources: CommandBarSources

    public init(mode: CommandBarMode, sources: CommandBarSources) {
        self.mode = mode
        self.sources = sources
        if case .currentTab(let address) = mode {
            query = address
        } else {
            query = ""
        }
        refresh()
    }

    /// Moves the highlight, stopping at the first and last rows.
    public func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    /// The action for a row, the highlighted one by default. Nil when there's nothing to activate.
    public func activate(at index: Int? = nil) -> CommandBarAction? {
        let index = index ?? selectedIndex
        guard results.indices.contains(index) else { return nil }
        let inNewTab = mode == .newTab
        switch results[index] {
        case .open(let url, _): return .open(url, inNewTab: inNewTab)
        case .tab(let tab): return .selectTab(tab.id)
        case .command(let command): return .runCommand(command.id)
        case .archived(let entry): return .restoreArchived(entry.id)
        case .history(let page): return .open(page.url, inNewTab: inNewTab)
        }
    }

    private func refresh() {
        results = commandBarResults(
            query: query,
            tabs: sources.tabs(),
            commands: sources.commands,
            archived: sources.archived(query),
            history: sources.history(query)
        )
        selectedIndex = 0
    }
}
