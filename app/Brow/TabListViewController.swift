import AppKit
import BrowserEngine
import Browsing

/// A plain list of open tabs. Temporary: the sidebar plan replaces it.
@MainActor
final class TabListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: BrowserWindowModel
    private let tableView = NSTableView()
    private var titles: [String] = []
    private var isUpdatingSelection = false

    init(model: BrowserWindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("title"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Close Tab", action: #selector(closeClickedTab(_:)), keyEquivalent: ""))
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keepObserving { [weak self] in self?.update() }
    }

    private func update() {
        titles = model.tabs.map { displayTitle(for: $0.state) }
        tableView.reloadData()
        isUpdatingSelection = true
        if let row = model.tabs.firstIndex(where: { $0.id == model.selectedTabID }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        isUpdatingSelection = false
    }

    @objc private func closeClickedTab(_ sender: Any?) {
        let row = tableView.clickedRow
        guard model.tabs.indices.contains(row) else { return }
        model.close(model.tabs[row].id)
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("tab")
        let label = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField ?? {
            let label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingTail
            return label
        }()
        label.stringValue = titles[row]
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, model.tabs.indices.contains(tableView.selectedRow) else { return }
        model.select(model.tabs[tableView.selectedRow].id)
    }
}
