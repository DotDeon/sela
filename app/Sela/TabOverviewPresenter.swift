import AppKit
import Browsing
import Favicons
import SidebarModel
import SidebarUI

/// View > Tab Overview: the current space's tabs as a grid of pictures over the window. Click or press Return to
/// switch to one, type to filter, Cmd+W or a tile's close button to close one, and Esc to go back.
@MainActor
final class TabOverviewPresenter {
    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let thumbnails: TabThumbnails
    private weak var host: NSView?
    private var overview: TabOverviewView?
    private weak var previousResponder: NSResponder?

    init(model: BrowserWindowModel, favicons: FaviconStore, host: NSView) {
        self.model = model
        self.favicons = favicons
        self.host = host
        thumbnails = TabThumbnails(model: model)
    }

    var isShowing: Bool { overview != nil }

    func toggle() {
        if isShowing { dismiss() } else { show() }
    }

    func show() {
        guard overview == nil, let host else { return }
        previousResponder = host.window?.firstResponder
        let view = TabOverviewView(model: model, favicons: favicons, thumbnails: thumbnails)
        view.onSelect = { [weak self] id in self?.select(id) }
        view.onClose = { [weak self] id in self?.model.close(id) }
        view.onDismiss = { [weak self] in self?.dismiss() }
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        overview = view
        view.focus()
        // Pages on screen draw now. Others keep the picture from when they were last shown.
        Task { await thumbnails.refresh(model.overviewItems.filter(\.isLive).map(\.id)) }

        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            view.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard let view = overview else { return }
        overview = nil
        let window = host?.window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            view.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { view.removeFromSuperview() }
        })
        if let page = model.selectedTab?.contentView, page.window != nil {
            window?.makeFirstResponder(page)
        } else if let previousResponder {
            window?.makeFirstResponder(previousResponder)
        }
    }

    /// Cmd+W while the overview shows closes the highlighted tab, not the one behind the overview.
    func closeHighlighted() {
        overview?.closeHighlighted()
    }

    private func select(_ id: ItemID) {
        model.select(id)
        // The page view is swapped in on the next pass of the main queue, so focus it after that.
        DispatchQueue.main.async { [weak self] in self?.dismiss() }
    }
}

/// The overview itself: a search field over a scrolling grid of tiles.
@MainActor
final class TabOverviewView: NSView, NSSearchFieldDelegate {
    var onSelect: ((ItemID) -> Void)?
    var onClose: ((ItemID) -> Void)?
    var onDismiss: (() -> Void)?

    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let thumbnails: TabThumbnails
    private let background = NSVisualEffectView()
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let grid = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var tiles: [ItemID: TabTileView] = [:]
    private var shown: [TabOverviewItem] = []
    private var highlighted = 0

    init(model: BrowserWindowModel, favicons: FaviconStore, thumbnails: TabThumbnails) {
        self.model = model
        self.favicons = favicons
        self.thumbnails = thumbnails
        super.init(frame: .zero)

        background.material = .underWindowBackground
        background.blendingMode = .withinWindow
        background.state = .active

        searchField.placeholderString = "Filter tabs"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 15)
        searchField.controlSize = .large
        searchField.focusRingType = .none

        scrollView.documentView = grid
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        for view in [background, scrollView, searchField, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            // Clear of the window's traffic lights.
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            searchField.centerXAnchor.constraint(equalTo: centerXAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 340),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 80),
        ])
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Takes clicks on the background, so they don't reach the page or sidebar behind.
    override func mouseDown(with event: NSEvent) {}

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    func closeHighlighted() {
        guard shown.indices.contains(highlighted) else { return }
        onClose?(shown[highlighted].id)
    }

    // MARK: Model

    private func update() {
        let items = filterOverview(model.overviewItems, query: searchField.stringValue)
        let images = thumbnails.images
        let previousID = shown.indices.contains(highlighted) ? shown[highlighted].id : nil
        let isFirstShow = tiles.isEmpty && shown.isEmpty
        shown = items

        for (id, tile) in tiles where !items.contains(where: { $0.id == id }) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for item in items {
            let tile = tiles[item.id] ?? makeTile(for: item.id)
            tile.show(item, image: images[item.id], favicon: favicons.image(forPage: item.url))
        }

        if isFirstShow, let selected = items.firstIndex(where: \.isSelected) {
            highlighted = selected
        } else if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            highlighted = index
        } else {
            highlighted = min(highlighted, max(items.count - 1, 0))
        }
        emptyLabel.stringValue = model.overviewItems.isEmpty ? "No tabs in this space" : "No tabs match"
        emptyLabel.isHidden = !items.isEmpty
        updateHighlight(scrolling: true)
        needsLayout = true
    }

    private func makeTile(for id: ItemID) -> TabTileView {
        let tile = TabTileView()
        tile.onClick = { [weak self] in self?.onSelect?(id) }
        tile.onClose = { [weak self] in self?.onClose?(id) }
        grid.addSubview(tile)
        tiles[id] = tile
        return tile
    }

    private func updateHighlight(scrolling: Bool) {
        for (index, item) in shown.enumerated() {
            tiles[item.id]?.isHighlighted = index == highlighted
        }
        if scrolling, shown.indices.contains(highlighted), let tile = tiles[shown[highlighted].id] {
            layoutGrid()
            grid.scrollToVisible(tile.frame.insetBy(dx: 0, dy: -20))
        }
    }

    override func layout() {
        super.layout()
        layoutGrid()
    }

    private var layoutGeometry: OverviewGrid {
        OverviewGrid(width: scrollView.contentSize.width, count: shown.count)
    }

    private func layoutGrid() {
        let width = scrollView.contentSize.width
        guard width > 0 else { return }
        let geometry = layoutGeometry
        grid.frame = CGRect(origin: .zero, size: CGSize(width: width, height: max(geometry.contentSize(for: shown.count).height, scrollView.contentSize.height)))
        for (index, item) in shown.enumerated() {
            tiles[item.id]?.frame = geometry.frame(at: index, width: width)
        }
    }

    // MARK: Field

    func controlTextDidChange(_ notification: Notification) {
        highlighted = 0
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let isEmpty = searchField.stringValue.isEmpty
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(.up)
        case #selector(NSResponder.moveDown(_:)): move(.down)
        // With nothing typed, left and right move between tiles instead of along the text.
        case #selector(NSResponder.moveLeft(_:)) where isEmpty: move(.left)
        case #selector(NSResponder.moveRight(_:)) where isEmpty: move(.right)
        case #selector(NSResponder.insertTab(_:)): move(.right)
        case #selector(NSResponder.insertBacktab(_:)): move(.left)
        case #selector(NSResponder.insertNewline(_:)):
            if shown.indices.contains(highlighted) { onSelect?(shown[highlighted].id) }
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        default: return false
        }
        return true
    }

    private func move(_ direction: OverviewGrid.Move) {
        highlighted = layoutGeometry.index(after: direction, from: highlighted, count: shown.count)
        updateHighlight(scrolling: true)
    }
}

/// One tab in the overview: its picture, or its icon while there's no picture, with its title underneath and a
/// close button that shows under the pointer.
@MainActor
final class TabTileView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var isHighlighted = false {
        didSet { updateBorder() }
    }

    private let picture = NSView()
    private let placeholder = NSImageView()
    private let icon = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = HoverButton(symbol: "xmark", label: "Close Tab", pointSize: 10, weight: .bold, size: 22)
    /// A round backing, so the close button shows up on any picture.
    private let closeBacking = NSView()
    private var isSelectedTab = false
    private var isHovered = false {
        didSet { closeBacking.isHidden = !isHovered }
    }

    init() {
        super.init(frame: .zero)
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 10
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.contentsGravity = .resizeAspectFill
        picture.layer?.borderWidth = 1

        placeholder.imageScaling = .scaleProportionallyUpOrDown
        icon.imageScaling = .scaleProportionallyUpOrDown
        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.contentTintColor = .labelColor
        closeButton.layer?.cornerRadius = 11
        closeBacking.isHidden = true
        closeBacking.wantsLayer = true
        closeBacking.layer?.cornerRadius = 11
        closeBacking.addSubview(closeButton)

        addSubview(picture)
        picture.addSubview(placeholder)
        for view in [icon, titleField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        closeBacking.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeBacking)
        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: closeBacking.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: closeBacking.centerYAnchor),
            closeBacking.widthAnchor.constraint(equalToConstant: 22),
            closeBacking.heightAnchor.constraint(equalToConstant: 22),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            titleField.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            closeBacking.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeBacking.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ item: TabOverviewItem, image: NSImage?, favicon: NSImage?) {
        titleField.stringValue = item.title
        toolTip = item.url?.absoluteString
        setAccessibilityLabel(item.title)
        icon.image = favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        picture.layer?.contents = image
        placeholder.isHidden = image != nil
        placeholder.image = favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        placeholder.contentTintColor = .tertiaryLabelColor
        isSelectedTab = item.isSelected
        updateBorder()
    }

    override func layout() {
        super.layout()
        picture.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - OverviewGrid.titleHeight)
        let side = min(picture.bounds.width, picture.bounds.height) * 0.28
        placeholder.frame = CGRect(x: (picture.bounds.width - side) / 2, y: (picture.bounds.height - side) / 2, width: side, height: side)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            picture.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            closeBacking.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
            if isHighlighted {
                picture.layer?.borderWidth = 3
                picture.layer?.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                picture.layer?.borderWidth = 1
                picture.layer?.borderColor = NSColor.separatorColor.cgColor
            }
        }
        titleField.textColor = isSelectedTab ? .controlAccentColor : .labelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    @objc private func closeClicked() { onClose?() }
}

/// Lays the grid out from the top down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
