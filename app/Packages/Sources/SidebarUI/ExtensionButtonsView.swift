import AppKit
import BrowserEngine

/// Extension buttons at the top of the sidebar, beside back and forward, like Arc's.
/// The puzzle piece lists every extension, for when the sidebar is too narrow to show all their buttons.
@MainActor
final class ExtensionButtonsView: NSStackView {
    var onClick: ((any BrowserExtension, NSView) -> Void)?
    var onManage: (() -> Void)?
    let moreButton = HoverButton(symbol: "puzzlepiece.extension", label: "Extensions")
    private(set) var buttons: [ExtensionButton] = []
    private var extensions: [any BrowserExtension] = []

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 0
        detachesHiddenViews = true
        moreButton.target = self
        moreButton.action = #selector(showMenu)
        addArrangedSubview(moreButton)
        setVisibilityPriority(.mustHold, for: moreButton)
        moreButton.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows a button for each extension that has one, as it looks in `tab`.
    func update(extensions: [any BrowserExtension], tab: (any BrowserTab)?) {
        self.extensions = extensions
        if buttons.map(\.extensionID) != extensions.map(\.id) {
            for button in buttons { removeArrangedSubview(button); button.removeFromSuperview() }
            buttons = extensions.enumerated().map { index, item in
                let button = ExtensionButton(extensionID: item.id)
                button.target = self
                button.action = #selector(buttonClicked(_:))
                insertArrangedSubview(button, at: index)
                // The first extensions stay longest as the sidebar narrows.
                setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: Float(500 - min(index, 400))), for: button)
                return button
            }
        }
        for (button, item) in zip(buttons, extensions) {
            let action = item.action(for: tab)
            button.isHidden = action == nil
            if let action { button.show(action, name: item.details.name) }
        }
        moreButton.isHidden = extensions.isEmpty
    }

    /// The button for an extension, or the puzzle piece when its button doesn't fit or it has none.
    func anchor(for id: String) -> NSView {
        buttons.first { $0.extensionID == id && !$0.isHidden && $0.window != nil && !detachedViews.contains($0) } ?? moreButton
    }

    @objc private func buttonClicked(_ sender: ExtensionButton) {
        guard let item = extensions.first(where: { $0.id == sender.extensionID }) else { return }
        onClick?(item, sender)
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        for item in extensions {
            let menuItem = NSMenuItem(title: item.details.name, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id
            menuItem.image = item.icon(size: 16).map(sized)
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "Manage Extensions…", action: #selector(manageChosen), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        let below = moreButton.isFlipped ? moreButton.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: moreButton)
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = extensions.first(where: { $0.id == id }) else { return }
        onClick?(item, anchor(for: id))
    }

    @objc private func manageChosen() { onManage?() }
}

/// One extension's button: its icon, dimmed when it's off for the page, with its badge in the corner.
@MainActor
final class ExtensionButton: HoverButton {
    let extensionID: String
    private let badge = NSTextField(labelWithString: "")

    init(extensionID: String) {
        self.extensionID = extensionID
        super.init(symbol: "puzzlepiece.extension", label: "Extension")
        badge.font = .systemFont(ofSize: 8, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 5
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1),
            badge.heightAnchor.constraint(equalToConstant: 10),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ action: ExtensionActionState, name: String) {
        let label = action.label.isEmpty ? name : action.label
        if let icon = action.icon {
            image = sized(icon)
            setAccessibilityLabel(label)
        } else {
            setSymbol("puzzlepiece.extension", label: label)
        }
        toolTip = label
        isEnabled = action.isEnabled
        // Badges are meant to be a few characters. Longer ones are cut so they stay on the icon.
        badge.stringValue = String(action.badgeText.prefix(4))
        badge.isHidden = action.badgeText.isEmpty
    }
}

/// A copy of an extension's icon drawn at 16 points.
private func sized(_ image: NSImage) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.size = NSSize(width: 16, height: 16)
    return copy
}
