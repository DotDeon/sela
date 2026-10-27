import AppKit

/// A sheet for choosing a space's icon from a grid of symbols or emoji, with a search field. Clicking an icon
/// chooses it; Remove Icon goes back to the plain dot.
@MainActor
final class SpaceIconPicker: NSViewController, NSSearchFieldDelegate {
    private let spaceTitle: String
    private let current: String?
    private let onChoose: (String?) -> Void
    private let kindControl = NSSegmentedControl(labels: ["Symbols", "Emoji"], trackingMode: .selectOne, target: nil, action: nil)
    private let search = NSSearchField()
    private let grid = IconGridView()
    private let empty = NSTextField(labelWithString: "No icons match")

    /// `onChoose` gets the chosen icon, or nil to remove it. It isn't called on Cancel.
    init(spaceTitle: String, current: String?, onChoose: @escaping (String?) -> Void) {
        self.spaceTitle = spaceTitle
        self.current = current
        self.onChoose = onChoose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let title = NSTextField(labelWithString: "Choose an icon for \(spaceTitle)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        // Open on the set the space's icon comes from.
        kindControl.selectedSegment = current.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil } == true ? 1 : 0
        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        search.placeholderString = "Search"
        search.delegate = self
        search.target = self
        search.action = #selector(searchChanged)

        grid.selected = current
        grid.onChoose = { [weak self] in self?.choose($0) }
        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        empty.textColor = .secondaryLabelColor
        empty.isHidden = true

        let remove = NSButton(title: "Remove Icon", target: self, action: #selector(removeIcon))
        remove.isEnabled = current != nil
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [remove, spacer, cancel])

        let stack = NSStackView(views: [title, kindControl, search, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: scroll)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        let inner: CGFloat = IconGridView.width(columns: IconGridView.columns)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: inner + 36),
            kindControl.widthAnchor.constraint(equalToConstant: inner),
            search.widthAnchor.constraint(equalToConstant: inner),
            scroll.widthAnchor.constraint(equalToConstant: inner),
            scroll.heightAnchor.constraint(equalToConstant: 260),
            buttons.widthAnchor.constraint(equalToConstant: inner),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: inner),
        ])
        empty.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        view = stack
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(search)
    }

    /// Return chooses the first icon shown.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if let first = grid.icons.first { choose(first) }
        return true
    }

    @objc private func kindChanged() { reload() }
    @objc private func searchChanged() { reload() }

    private func reload() {
        let kind: SpaceIconKind = kindControl.selectedSegment == 1 ? .emoji : .symbols
        grid.icons = spaceIconChoices(kind, matching: search.stringValue) {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
        empty.isHidden = !grid.icons.isEmpty
        grid.enclosingScrollView?.contentView.scroll(to: .zero)
    }

    private func choose(_ icon: String?) {
        onChoose(icon)
        close()
    }

    @objc private func removeIcon() { choose(nil) }
    @objc private func cancel() { close() }

    private func close() {
        guard let sheet = view.window else { return }
        sheet.sheetParent?.endSheet(sheet)
    }

    /// Shows the picker as a sheet on `window`.
    static func present(on window: NSWindow, spaceTitle: String, current: String?, onChoose: @escaping (String?) -> Void) {
        let picker = SpaceIconPicker(spaceTitle: spaceTitle, current: current, onChoose: onChoose)
        let sheet = NSPanel(contentViewController: picker)
        sheet.styleMask = [.titled]
        window.beginSheet(sheet)
    }
}

/// The icons as a grid of buttons, laid out in rows from the top.
@MainActor
private final class IconGridView: NSView {
    static let columns = 8
    static let cell: CGFloat = 40
    static let gap: CGFloat = 4
    static func width(columns: Int) -> CGFloat { CGFloat(columns) * cell + CGFloat(columns - 1) * gap }

    var selected: String?
    var onChoose: ((String) -> Void)?
    var icons: [String] = [] {
        didSet { rebuild() }
    }

    override var isFlipped: Bool { true }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let rows = (icons.count + Self.columns - 1) / Self.columns
        setFrameSize(NSSize(width: Self.width(columns: Self.columns), height: max(CGFloat(rows) * (Self.cell + Self.gap) - Self.gap, 0)))
        for (index, icon) in icons.enumerated() {
            let button = IconButton(icon: icon, isSelected: icon == selected)
            button.target = self
            button.action = #selector(clicked(_:))
            let column = index % Self.columns, row = index / Self.columns
            button.frame = NSRect(x: CGFloat(column) * (Self.cell + Self.gap), y: CGFloat(row) * (Self.cell + Self.gap), width: Self.cell, height: Self.cell)
            addSubview(button)
        }
    }

    @objc private func clicked(_ sender: IconButton) {
        onChoose?(sender.icon)
    }
}

/// One icon in the grid, with a soft square behind it on hover and behind the space's current icon.
@MainActor
private final class IconButton: NSButton {
    let icon: String
    private let isSelected: Bool
    private var isHovered = false {
        didSet { updateBackground() }
    }

    init(icon: String, isSelected: Bool) {
        self.icon = icon
        self.isSelected = isSelected
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        if let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: icon) {
            image = symbol.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            imagePosition = .imageOnly
            contentTintColor = .labelColor
        } else {
            title = icon
            font = .systemFont(ofSize: 22)
            imagePosition = .noImage
        }
        toolTip = icon
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override var isHighlighted: Bool {
        didSet { updateBackground() }
    }

    private func updateBackground() {
        let alpha: CGFloat = isHighlighted ? 0.18 : isSelected ? 0.14 : isHovered ? 0.08 : 0
        layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor : .labelColor).withAlphaComponent(alpha).cgColor
    }
}
