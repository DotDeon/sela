import AppKit

/// A tab or folder row: icon, title, and buttons that appear on hover.
final class ItemCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("item")

    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let resetButton = NSButton()
    let closeButton = NSButton()

    var onClose: (() -> Void)?
    var onReset: (() -> Void)?
    var onRename: ((String) -> Void)?
    var showsCloseOnHover = true
    var showsReset = false {
        didSet { resetButton.isHidden = !showsReset }
    }

    private var isHovered = false {
        didSet { closeButton.isHidden = !(isHovered && showsCloseOnHover) }
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
        configureButton(resetButton, symbol: "arrow.uturn.backward", label: "Back to Saved Address", action: #selector(resetTapped))
        configureButton(closeButton, symbol: "xmark", label: "Close", action: #selector(closeTapped))
        resetButton.isHidden = true
        closeButton.isHidden = true

        for view in [iconView, titleField, resetButton, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 4),
            resetButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: resetButton.trailingAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

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

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
    }
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
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            line.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -6),
            line.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            newTabButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            newTabButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setClearVisible(_ visible: Bool) {
        clearButton.isHidden = !visible
    }

    @objc private func clearTapped() { onClear?() }

    @objc private func newTabTapped() { onNewTab?() }
}
