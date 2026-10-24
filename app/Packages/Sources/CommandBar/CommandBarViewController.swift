import AppKit
import SidebarUI

/// The command bar panel: a search field over a list of results. The owner shows and hides it.
@MainActor
public final class CommandBarViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 640
    static let fieldHeight: CGFloat = 48
    static let rowHeight: CGFloat = 40
    static let visibleRows = 8

    let searchField = NSTextField()
    let tableView = NSTableView()
    private let model: CommandBarModel
    private let icon: @MainActor (CommandBarResult) -> NSImage?
    private let onAction: (CommandBarAction) -> Void
    private let onDismiss: () -> Void
    private var shownResults: [CommandBarResult] = []
    private var tableHeight: NSLayoutConstraint!

    public init(
        model: CommandBarModel,
        icon: @escaping @MainActor (CommandBarResult) -> NSImage?,
        onAction: @escaping (CommandBarAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.icon = icon
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func loadView() {
        let panel = CommandBarPanelView()
        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.masksToBounds = true

        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 20)
        searchField.placeholderString = "Search or enter address"
        searchField.stringValue = model.query
        searchField.delegate = self
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false

        let separator = NSBox()
        separator.boxType = .separator

        let column = NSTableColumn(identifier: .init("result"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.refusesFirstResponder = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        for subview in [searchField, separator, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(subview)
        }
        tableHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        // The presenter caps the width so the panel fits narrow windows.
        let preferredWidth = panel.widthAnchor.constraint(equalToConstant: Self.width)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            searchField.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            searchField.heightAnchor.constraint(equalToConstant: Self.fieldHeight - 18),
            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            separator.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
            tableHeight,
        ])
        view = panel
        keepObserving { [weak self] in self?.update() }
    }

    /// Puts the cursor in the field with its text selected.
    public func focus() {
        view.window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    private func update() {
        let results = model.results
        let selected = model.selectedIndex
        if results != shownResults {
            shownResults = results
            tableView.reloadData()
            tableHeight.constant = CGFloat(min(results.count, Self.visibleRows)) * Self.rowHeight
        }
        if results.indices.contains(selected) {
            tableView.selectRowIndexes([selected], byExtendingSelection: false)
            tableView.scrollRowToVisible(selected)
        }
    }

    private func activate(_ index: Int? = nil) {
        if let action = model.activate(at: index) {
            onAction(action)
        }
    }

    @objc private func rowClicked() {
        guard tableView.clickedRow >= 0 else { return }
        activate(tableView.clickedRow)
    }

    // MARK: Field

    public func controlTextDidChange(_ notification: Notification) {
        model.query = searchField.stringValue
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            activate()
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss()
        default:
            return false
        }
        return true
    }

    // MARK: Table

    public func numberOfRows(in tableView: NSTableView) -> Int {
        shownResults.count
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CommandBarTableRowView()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: CommandBarRowView.identifier, owner: nil) as? CommandBarRowView ?? CommandBarRowView()
        let result = shownResults[row]
        let (title, detail, symbol) = describe(result)
        cell.titleField.stringValue = title
        cell.detailField.stringValue = detail
        cell.iconView.image = icon(result) ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return cell
    }

    /// A row's title, right-hand hint and fallback symbol.
    private func describe(_ result: CommandBarResult) -> (String, String, String) {
        switch result {
        case .open(let url, let search):
            if let search {
                return ("Search \(search.name) for “\(model.query.trimmingCharacters(in: .whitespacesAndNewlines))”", "", "magnifyingglass")
            }
            let path = url.path() == "/" ? "" : url.path()
            return ("Open \(url.host() ?? url.absoluteString)\(path)", "", "globe")
        case .tab(let tab):
            return (tab.title, tab.location ?? "Switch to Tab", "square.on.square")
        case .command(let command):
            return (command.title, "", "command")
        case .archived(let entry):
            return (entry.title, "Restore", "archivebox")
        case .history(let page):
            return (page.title, page.url.host() ?? "", "clock")
        }
    }
}

/// The panel's background. Keeps clicks on its padding, so they don't reach the backdrop behind it and close the bar.
final class CommandBarPanelView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {}
}
