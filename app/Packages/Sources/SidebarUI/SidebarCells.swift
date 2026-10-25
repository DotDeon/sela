import AppKit

/// A tab or folder row: icon, title, and buttons that appear on hover.
class ItemCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("item")

    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    /// Shows while the page makes sound. A click mutes the tab, and the symbol gets a slash until it's unmuted.
    let audioButton = HoverButton(symbol: "speaker.wave.2.fill", label: "Mute Tab", pointSize: 11, weight: .semibold, size: 22)
    let resetButton = HoverButton(symbol: "arrow.uturn.backward", label: "Back to Saved Address", pointSize: 11, weight: .semibold, size: 22)
    let closeButton = HoverButton(symbol: "xmark", label: "Close", pointSize: 11, weight: .semibold, size: 22)
    /// The buttons at the trailing end. Hidden ones take no room.
    let buttons = NSStackView()

    var onClose: (() -> Void)?
    var onReset: (() -> Void)?
    var onToggleMute: (() -> Void)?
    var onRename: ((String) -> Void)?
    var showsCloseOnHover = true
    var showsReset = false {
        didSet { resetButton.isHidden = !showsReset }
    }

    /// Set by the row, which the outline view keeps up to date.
    var isHovered = false {
        didSet { closeButton.isHidden = !(isHovered && showsCloseOnHover) }
    }

    private var shownAudio: (playing: Bool, muted: Bool)?

    /// Shows the speaker while the page plays sound or is muted. A new symbol only when that changes.
    func showAudio(playing: Bool, muted: Bool) {
        guard shownAudio?.playing != playing || shownAudio?.muted != muted else { return }
        shownAudio = (playing, muted)
        audioButton.isHidden = !(playing || muted)
        let label = muted ? "Unmute Tab" : "Mute Tab"
        audioButton.setSymbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: label, pointSize: 11, weight: .semibold)
        audioButton.toolTip = label
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        imageView = iconView
        textField = titleField

        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 13)
        titleField.delegate = self
        audioButton.target = self
        audioButton.action = #selector(audioTapped)
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        audioButton.isHidden = true
        resetButton.isHidden = true
        closeButton.isHidden = true
        buttons.orientation = .horizontal
        buttons.spacing = 2
        for button in [audioButton, resetButton, closeButton] {
            buttons.addArrangedSubview(button)
        }

        for view in [iconView, titleField, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 4),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    /// Turns the title into an editable field until Return or Escape.
    func beginRenaming(currentTitle: String) {
        titleField.isEditable = true
        titleField.stringValue = currentTitle
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard titleField.isEditable else { return }
        titleField.isEditable = false
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        if movement != NSTextMovement.cancel.rawValue {
            onRename?(titleField.stringValue)
        }
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func resetTapped() { onReset?() }

    @objc private func audioTapped() { onToggleMute?() }
}

/// A split view's row: one segment per pane, each with its icon and title, and a close button on hover.
/// Clicking a segment shows that pane.
final class SplitCellView: ItemCellView {
    static let splitIdentifier = NSUserInterfaceItemIdentifier("split")

    var onSelectPane: ((Int) -> Void)?
    private let stack = NSStackView()
    private var segments: [NSButton] = []

    var segmentTitles: [String] { segments.map(\.title) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.splitIdentifier
        iconView.isHidden = true
        titleField.isHidden = true
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: buttons.leadingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// One segment per pane. The focused pane's title is brighter than the others.
    func configure(panes: [(title: String, icon: NSImage?, isFocused: Bool)]) {
        if segments.count != panes.count {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            segments = panes.indices.map { index in
                let button = NSButton(title: "", target: self, action: #selector(segmentTapped(_:)))
                button.tag = index
                button.bezelStyle = .inline
                button.isBordered = false
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true
                button.alignment = .left
                button.lineBreakMode = .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                return button
            }
            for (index, button) in segments.enumerated() {
                if index > 0 {
                    let line = NSBox()
                    line.boxType = .custom
                    line.borderWidth = 0
                    line.fillColor = .separatorColor
                    line.widthAnchor.constraint(equalToConstant: 1).isActive = true
                    stack.addArrangedSubview(line)
                }
                stack.addArrangedSubview(button)
            }
            // Equal widths for the segments only, not the separators.
            for button in segments.dropFirst() {
                button.widthAnchor.constraint(equalTo: segments[0].widthAnchor).isActive = true
            }
        }
        for (button, pane) in zip(segments, panes) {
            button.image = pane.icon.map { icon in
                let sized = icon.copy() as! NSImage
                sized.size = NSSize(width: 16, height: 16)
                return sized
            }
            button.attributedTitle = NSAttributedString(string: pane.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: pane.isFocused ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
        }
    }

    func selectSegment(_ index: Int) { onSelectPane?(index) }

    @objc private func segmentTapped(_ sender: NSButton) { selectSegment(sender.tag) }
}

/// The line between pinned and unpinned tabs, with "Clear" and "+ New Tab".
final class DividerCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("divider")
    static let height: CGFloat = 60

    var onClear: (() -> Void)?
    var onNewTab: (() -> Void)?

    private let line = NSBox()
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let newTabButton = NSButton(title: "New Tab", target: nil, action: nil)
    private var lineToClear: NSLayoutConstraint!
    private var lineToEdge: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        line.boxType = .separator

        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11, weight: .medium)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.toolTip = "Close all unpinned tabs"

        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        newTabButton.imagePosition = .imageLeading
        newTabButton.font = .systemFont(ofSize: 13)
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.target = self
        newTabButton.action = #selector(newTabTapped)

        for view in [line, clearButton, newTabButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        lineToClear = line.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6)
        lineToEdge = line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            lineToClear,
            line.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            newTabButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            newTabButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var isClearVisible: Bool { !clearButton.isHidden }

    /// Without Clear, the line runs the whole width instead of stopping where the button would be.
    func setClearVisible(_ visible: Bool) {
        clearButton.isHidden = !visible
        lineToClear.isActive = visible
        lineToEdge.isActive = !visible
    }

    @objc private func clearTapped() { onClear?() }

    @objc private func newTabTapped() { onNewTab?() }
}
