import AppKit
import BrowserEngine
import Browsing
import Favicons
import Sidebar
import SidebarModel

/// An outline view that counts full reloads, so tests can check updates animate instead.
final class SidebarOutlineView: NSOutlineView {
    private(set) var reloadCount = 0

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
        updateHover()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { updateHover() }

    override func mouseEntered(with event: NSEvent) { updateHover() }

    override func mouseExited(with event: NSEvent) { updateHover() }

    override func endUpdates() {
        super.endUpdates()
        updateHover()
    }

    override func didAdd(_ rowView: NSTableRowView, forRow row: Int) {
        super.didAdd(rowView, forRow: row)
        (rowView as? SidebarRowView)?.isHovered = row == hoveredRow()
    }

    /// Marks only the row under the pointer as hovered. Called whenever the pointer or the rows move.
    func updateHover() {
        let hovered = hoveredRow()
        enumerateAvailableRowViews { rowView, row in
            (rowView as? SidebarRowView)?.isHovered = row == hovered
        }
    }

    private func hoveredRow() -> Int {
        guard let window, window.isKeyWindow || window.isMainWindow else { return -1 }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return visibleRect.contains(point) ? row(at: point) : -1
    }

    /// No indentation marker frame for the divider; folders keep the disclosure triangle.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        guard let node = item(atRow: row) as? OutlineNode, case .item = node.row else { return .zero }
        return super.frameOfOutlineCell(atRow: row)
    }
}

/// `NSOutlineView` needs objects with stable identity. One node per row, reused across updates.
final class OutlineNode: NSObject {
    let row: OutlineRow

    init(_ row: OutlineRow) {
        self.row = row
    }

    var itemID: ItemID? {
        if case .item(let id) = row { return id }
        return nil
    }
}

/// One space: its title and an outline of pinned tabs and folders, the divider, and unpinned tabs.
@MainActor
final class SpacePageView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let spaceID: SpaceID
    let outlineView = SidebarOutlineView()
    /// Receives horizontal swipes that start over this page.
    weak var horizontalScrollTarget: NSResponder? {
        didSet { scrollView.horizontalScrollTarget = horizontalScrollTarget }
    }
    var onNewTab: (() -> Void)?

    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let titleField = NSTextField(labelWithString: "")
    private let scrollView = SidebarPageScrollView()
    private var nodes: [OutlineRow: OutlineNode] = [:]
    private var snapshot: OutlineSnapshot = [:]
    private var isApplyingModel = false

    private var sidebar: SidebarStore { model.sidebar }
    private var document: SidebarDocument { model.sidebar.document }

    init(spaceID: SpaceID, model: BrowserWindowModel, favicons: FaviconStore) {
        self.spaceID = spaceID
        self.model = model
        self.favicons = favicons
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        buildViews()
        if let space = document.space(spaceID) {
            snapshot = outlineSnapshot(for: space, in: document)
        }
        outlineView.reloadData()
        syncExpansion()
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Building

    private func buildViews() {
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        titleField.lineBreakMode = .byTruncatingTail

        let column = NSTableColumn(identifier: .init("main"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.style = .plain
        outlineView.indentationPerLevel = 14
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.rowSizeStyle = .custom
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.registerForDraggedTypes([.sidebarItem, .URL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .gap
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none

        for view in [titleField, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Updating

    /// Applies the sidebar's current state: animated row changes, folder expansion, titles, icons and selection.
    private func update() {
        guard let space = document.space(spaceID) else { return }
        titleField.stringValue = space.title ?? ""

        let newSnapshot = outlineSnapshot(for: space, in: document)
        let updates = outlineUpdates(from: snapshot, to: newSnapshot)
        snapshot = newSnapshot
        isApplyingModel = true
        if !updates.isEmpty {
            outlineView.beginUpdates()
            for update in updates {
                switch update {
                case .remove(let parent, let index):
                    outlineView.removeItems(at: [index], inParent: parent.map(node), withAnimation: .effectFade)
                case .insert(let parent, let index):
                    outlineView.insertItems(at: [index], inParent: parent.map(node), withAnimation: .slideDown)
                }
            }
            outlineView.endUpdates()
        }
        syncExpansion()
        refreshVisibleRows()
        syncSelection()
        isApplyingModel = false
    }

    private func syncExpansion() {
        // Expanding a folder adds rows below it, so the row count is reread each time.
        var row = 0
        while row < outlineView.numberOfRows {
            defer { row += 1 }
            guard let node = outlineView.item(atRow: row) as? OutlineNode, let id = node.itemID,
                  case .folder(let info) = document.item(id)?.kind
            else { continue }
            if info.isExpanded, !outlineView.isItemExpanded(node) {
                outlineView.animator().expandItem(node)
            } else if !info.isExpanded, outlineView.isItemExpanded(node) {
                outlineView.animator().collapseItem(node)
            }
        }
    }

    private func refreshVisibleRows() {
        let visible = outlineView.rows(in: outlineView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<(visible.location + visible.length) {
            guard let node = outlineView.item(atRow: row) as? OutlineNode else { continue }
            if let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                configure(cell, for: node)
            }
        }
    }

    private func syncSelection() {
        guard let selected = model.selectedItemID, let row = rowIndex(for: selected) else {
            outlineView.deselectAll(nil)
            return
        }
        if outlineView.selectedRow != row {
            outlineView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    /// A pane's row is its split's row.
    private func rowIndex(for id: ItemID) -> Int? {
        guard let node = nodes[.item(document.splitID(containing: id) ?? id)] else { return nil }
        let row = outlineView.row(forItem: node)
        return row >= 0 ? row : nil
    }

    private func node(_ row: OutlineRow) -> OutlineNode {
        if let existing = nodes[row] { return existing }
        let created = OutlineNode(row)
        nodes[row] = created
        return created
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        rows(under: item as? OutlineNode).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(rows(under: item as? OutlineNode)[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let id = (item as? OutlineNode)?.itemID, case .folder = document.item(id)?.kind else { return false }
        return true
    }

    private func rows(under parent: OutlineNode?) -> [OutlineRow] {
        guard let parent else {
            return document.space(spaceID).map { rootRows(for: $0, in: document) } ?? []
        }
        guard let id = parent.itemID else { return [] }
        return childRows(of: id, in: document)
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? OutlineNode)?.row == .divider ? DividerCellView.height : 32
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = SidebarRowView()
        rowView.showsHover = (item as? OutlineNode)?.row != .divider
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        let cell: NSView
        switch node.row {
        case .divider:
            let divider = outlineView.makeView(withIdentifier: DividerCellView.identifier, owner: nil) as? DividerCellView ?? DividerCellView()
            divider.onClear = { [weak self] in self?.model.clearUnpinned() }
            divider.onNewTab = { [weak self] in self?.onNewTab?() }
            cell = divider
        case .item(let id):
            if case .split = document.item(id)?.kind {
                cell = outlineView.makeView(withIdentifier: SplitCellView.splitIdentifier, owner: nil) as? SplitCellView ?? SplitCellView()
            } else {
                cell = outlineView.makeView(withIdentifier: ItemCellView.identifier, owner: nil) as? ItemCellView ?? ItemCellView()
            }
        }
        configure(cell, for: node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let id = (item as? OutlineNode)?.itemID, case .tab = document.item(id)?.kind else { return false }
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        recordExpansion(notification, expanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        recordExpansion(notification, expanded: false)
    }

    private func recordExpansion(_ notification: Notification, expanded: Bool) {
        guard !isApplyingModel, let node = notification.userInfo?["NSObject"] as? OutlineNode, let id = node.itemID else { return }
        sidebar.setExpanded(id, expanded)
    }

    private func configure(_ view: NSView, for node: OutlineNode) {
        if let divider = view as? DividerCellView {
            let unpinned = document.space(spaceID).flatMap { document.item($0.unpinnedContainerID) }
            divider.setClearVisible(!(unpinned?.childIDs.isEmpty ?? true))
            return
        }
        guard let cell = view as? ItemCellView, let id = node.itemID, let item = document.item(id) else { return }
        // Leave a row alone while it's being renamed, so other changes don't wipe what the user is typing.
        guard !cell.titleField.isEditable else { return }
        switch item.kind {
        case .folder(let info):
            cell.titleField.stringValue = item.title ?? "Folder"
            cell.iconView.image = info.icon.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
                ?? NSImage(systemSymbolName: info.isExpanded ? "folder" : "folder.fill", accessibilityDescription: "Folder")
            cell.iconView.contentTintColor = .secondaryLabelColor
            cell.showsCloseOnHover = false
            cell.showsReset = false
        case .split:
            let panes = item.childIDs
            (cell as? SplitCellView)?.configure(panes: panes.map { pane in
                let shown = model.pageForDisplay(for: pane)
                let saved: URL? = if case .tab(let info) = document.item(pane)?.kind { info.savedURL } else { nil }
                let title = document.item(pane).map { sidebarTitle(for: $0, liveState: shown) } ?? ""
                let page = shown?.url ?? saved
                let icon = favicons.image(forPage: page) ?? letterImage(for: page?.host() ?? title, size: 16)
                return (title, icon, pane == model.selectedItemID)
            })
            (cell as? SplitCellView)?.onSelectPane = { [weak self] index in
                guard let self, let pane = document.item(id)?.childIDs[safe: index] else { return }
                model.select(pane)
            }
            cell.showsCloseOnHover = true
            cell.showsReset = false
            cell.onClose = { [weak self] in self?.model.closeSplit(id) }
        case .tab(let info):
            let live = model.liveTab(for: id)
            let state = live?.state
            let shown = model.pageForDisplay(for: id)
            cell.titleField.stringValue = sidebarTitle(for: item, liveState: shown)
            if let icon = state?.faviconURL, let page = state?.url {
                favicons.remember(iconURL: icon, forPage: page)
            }
            let page = shown?.url ?? info.savedURL
            cell.iconView.image = favicons.image(forPage: page)
                ?? letterImage(for: page?.host() ?? cell.titleField.stringValue, size: 16)
            cell.iconView.contentTintColor = nil
            cell.titleField.textColor = live == nil ? .secondaryLabelColor : .labelColor
            // Closing a pinned tab only unloads it, so there's nothing to close until its page is loaded.
            let isUnpinned: Bool
            if case .unpinned = document.containerRole(of: id) { isUnpinned = true } else { isUnpinned = false }
            cell.showsCloseOnHover = isUnpinned || live != nil
            cell.showsReset = model.isAwayFromSavedURL(id)
            cell.onClose = { [weak self] in self?.model.close(id) }
            cell.onReset = { [weak self] in self?.model.resetToSavedURL(id) }
        case .container:
            break
        }
        cell.onRename = { [weak self] text in self?.sidebar.rename(id, to: text) }
    }

    // MARK: Clicking

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode, let id = node.itemID,
              let item = document.item(id)
        else { return }
        switch item.kind {
        case .tab, .split: model.select(id)
        case .folder(let info): sidebar.setExpanded(id, !info.isExpanded)
        case .container: break
        }
    }

    /// Starts renaming an item in place.
    func beginRenaming(_ id: ItemID) {
        guard let row = rowIndex(for: id),
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ItemCellView,
              let item = document.item(id)
        else { return }
        outlineView.scrollRowToVisible(row)
        cell.beginRenaming(currentTitle: item.title ?? cell.titleField.stringValue)
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let id = (item as? OutlineNode)?.itemID else { return nil }
        return pasteboardItem(for: id)
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        var parent = item as? OutlineNode
        var childIndex = index
        // A drop onto a tab lands just above it instead.
        if let id = parent?.itemID, case .tab = document.item(id)?.kind, index == -1 {
            let parentNode = outlineView.parent(forItem: parent) as? OutlineNode
            childIndex = outlineView.childIndex(forItem: parent!)
            parent = parentNode
            outlineView.setDropItem(parent, dropChildIndex: childIndex)
        }
        guard let space = document.space(spaceID),
              let destination = dropDestination(parent: parent?.row, childIndex: childIndex, space: space, document: document)
        else { return [] }
        if let dragged = draggedItemID(info) {
            return document.canMove(dragged, to: destination.parent) ? .move : []
        }
        return draggedURL(info) != nil ? .copy : []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let space = document.space(spaceID),
              let destination = dropDestination(parent: (item as? OutlineNode)?.row, childIndex: index, space: space, document: document)
        else { return false }
        if let dragged = draggedItemID(info) {
            var target = destination.index
            // The index counts the dragged item in its old place; moving down within the same parent shifts by one.
            if let current = target, let item = document.item(dragged), item.parentID == destination.parent,
               let oldIndex = document.item(destination.parent)?.childIDs.firstIndex(of: dragged), oldIndex < current {
                target = current - 1
            }
            return (try? sidebar.move(dragged, to: destination.parent, at: target)) != nil
        }
        if let url = draggedURL(info) {
            sidebar.createTab(url: url, title: nil, in: destination.parent, at: destination.index)
            return true
        }
        return false
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let row = outlineView.clickedRow
        let id = row >= 0 ? (outlineView.item(atRow: row) as? OutlineNode)?.itemID : nil
        menuItems(for: id).forEach(menu.addItem)
    }

    /// The context menu for an item's row, or for empty space when `id` is nil.
    func menuItems(for id: ItemID?) -> [NSMenuItem] {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let id, let item = document.item(id) else {
            menu.addItem(menuItem("New Folder") { [weak self] in self?.newFolder(in: nil) })
            let items = menu.items
            menu.removeAllItems()
            return items
        }
        switch item.kind {
        case .tab(let info):
            menu.addItem(menuItem("Rename…") { [weak self] in self?.beginRenaming(id) })
            let pinned: Bool
            if case .pinned = document.containerRole(of: id) { pinned = true } else { pinned = false }
            menu.addItem(menuItem(pinned ? "Unpin" : "Pin") { [weak self] in self?.model.togglePin(id) })
            menu.addItem(menuItem("Add to Favourites") { [weak self] in self?.sidebar.addToFavorites(id) })
            let url = model.currentPage(for: id)?.url ?? info.savedURL
            menu.addItem(menuItem("Copy URL") {
                guard let url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            })
            if model.isAwayFromSavedURL(id) {
                menu.addItem(menuItem("Back to Saved Address") { [weak self] in self?.model.resetToSavedURL(id) })
            }
            let split = menuItem("Open in Split View") { [weak self] in self?.model.openInSplit(id) }
            split.isEnabled = model.canOpenInSplit(id)
            menu.addItem(split)
            menu.addItem(.separator())
            menu.addItem(menuItem("Close") { [weak self] in self?.model.close(id) })
            if pinned {
                menu.addItem(menuItem("Delete") { [weak self] in self?.model.delete(id) })
            }
        case .folder:
            menu.addItem(menuItem("Rename…") { [weak self] in self?.beginRenaming(id) })
            menu.addItem(menuItem("New Folder Inside") { [weak self] in self?.newFolder(in: id) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete Folder…") { [weak self] in self?.deleteFolder(id) })
        case .split:
            menu.addItem(menuItem("Separate Split View") { [weak self] in self?.sidebar.separateSplit(id) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Close Split View") { [weak self] in self?.model.closeSplit(id) })
        case .container:
            break
        }
        let items = menu.items
        menu.removeAllItems()
        return items
    }

    /// Makes a folder at the top of the pinned section, or inside `parent`, and starts renaming it.
    func newFolder(in parent: ItemID?) {
        guard let container = parent ?? document.space(spaceID)?.pinnedContainerID else { return }
        if let parent { sidebar.setExpanded(parent, true) }
        let id = sidebar.createFolder(title: "New Folder", in: container, at: 0)
        Task { @MainActor [weak self] in
            // Wait for the observation update to insert the row.
            try? await Task.sleep(for: .milliseconds(50))
            self?.beginRenaming(id)
        }
    }

    private func deleteFolder(_ id: ItemID) {
        let tabCount = document.tabIDs(under: id).count
        guard tabCount > 0 else {
            sidebar.remove(id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete this folder and its \(tabCount) \(tabCount == 1 ? "tab" : "tabs")?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            for tab in self?.document.tabIDs(under: id) ?? [] {
                self?.model.close(tab)
            }
            self?.sidebar.remove(id)
        }
    }
}

/// A menu item that runs a closure.
@MainActor
func menuItem(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
    let target = ClosureTarget(action)
    item.target = target
    item.representedObject = target
    return item
}

@MainActor
final class ClosureTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}

/// A page's vertical scroll view. Gestures that start mostly sideways go to the space pager instead.
final class SidebarPageScrollView: NSScrollView {
    weak var horizontalScrollTarget: NSResponder?
    private var forwardingGesture = false

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin {
            forwardingGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        // Mouse wheels have no phase; only trackpad gestures and their momentum are forwarded.
        let isGesture = event.phase != [] || event.momentumPhase != []
        if forwardingGesture, isGesture, let target = horizontalScrollTarget {
            target.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
        // The rows moved under a still pointer.
        (documentView as? SidebarOutlineView)?.updateHover()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
