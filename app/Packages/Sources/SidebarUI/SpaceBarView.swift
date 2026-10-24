import AppKit
import Browsing
import Sidebar
import SidebarModel

/// A button per space along the bottom of the sidebar, plus one to add a space.
@MainActor
final class SpaceBarView: NSView {
    private let model: BrowserWindowModel
    private let stack = NSStackView()
    private let addButton = HoverButton(symbol: "plus", label: "New Space", pointSize: 13)
    /// Opens this session's downloads.
    let downloadsButton = HoverButton(symbol: "arrow.down.circle", label: "Downloads", pointSize: 13)
    private var buttons: [SpaceButton] = []

    init(model: BrowserWindowModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY

        addButton.target = self
        addButton.action = #selector(addSpace)

        for view in [stack, addButton, downloadsButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: downloadsButton.trailingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -4),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            downloadsButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            downloadsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var document: SidebarDocument { model.sidebar.document }

    private func update() {
        let spaces = document.spaces
        if buttons.map(\.spaceID) != spaces.map(\.id) {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = spaces.map { space in
                let button = SpaceButton(spaceID: space.id)
                button.target = self
                button.action = #selector(spaceClicked(_:))
                button.onDrop = { [weak self] id in self?.moveItem(id, to: space.id) }
                return button
            }
            buttons.forEach(stack.addArrangedSubview)
        }
        for (button, space) in zip(buttons, spaces) {
            // Made again each time, so the Profile menu shows profiles added or renamed since.
            button.menu = spaceMenu(for: space.id)
            configureSpaceIcon(button, icon: space.icon, title: space.title)
            let selected = space.id == model.selectedSpaceID
            button.contentTintColor = selected ? .labelColor : .tertiaryLabelColor
            button.font = .systemFont(ofSize: 14)
            button.isCurrent = selected
        }
    }

    @objc private func spaceClicked(_ sender: SpaceButton) {
        model.selectSpace(sender.spaceID)
    }

    @objc private func addSpace() {
        let id = model.sidebar.addSpace(title: "New Space")
        model.selectSpace(id)
    }

    /// Moves a dragged item to the top of the matching section in another space.
    private func moveItem(_ id: ItemID, to spaceID: SpaceID) {
        guard let space = document.space(spaceID) else { return }
        let container: ItemID
        if case .pinned = document.containerRole(of: id) {
            container = space.pinnedContainerID
        } else {
            container = space.unpinnedContainerID
        }
        try? model.sidebar.move(id, to: container, at: 0)
    }

    func spaceMenu(for id: SpaceID) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Rename…") { [weak self] in self?.rename(id) })
        menu.addItem(menuItem("Change Icon…") { [weak self] in self?.changeIcon(id) })
        let colours = NSMenuItem(title: "Colour", action: nil, keyEquivalent: "")
        let colourMenu = NSMenu()
        let names = ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Grey"]
        for (name, colour) in zip(names, defaultSpaceColors) {
            let item = menuItem(name) { [weak self] in self?.setColour(colour, for: id) }
            item.image = swatch(NSColor(colour))
            colourMenu.addItem(item)
        }
        colours.submenu = colourMenu
        menu.addItem(colours)
        menu.addItem(profileItem(for: id))
        menu.addItem(.separator())
        menu.addItem(menuItem("Move Left") { [weak self] in self?.move(id, by: -1) })
        menu.addItem(menuItem("Move Right") { [weak self] in self?.move(id, by: 1) })
        menu.addItem(.separator())
        let delete = menuItem("Delete Space…") { [weak self] in self?.delete(id) }
        menu.addItem(delete)
        menu.autoenablesItems = false
        delete.isEnabled = document.spaces.count > 1
        return menu
    }

    /// Profile: every profile, with a tick by the space's, then New Profile….
    private func profileItem(for id: SpaceID) -> NSMenuItem {
        let item = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = document.profileID(of: id)
        for profile in document.profiles {
            let choice = menuItem(profile.name) { [weak self] in self?.model.sidebar.setProfile(profile.id, of: id) }
            choice.state = profile.id == current ? .on : .off
            submenu.addItem(choice)
        }
        submenu.addItem(.separator())
        submenu.addItem(menuItem("New Profile…") { [weak self] in self?.newProfile(for: id) })
        item.submenu = submenu
        return item
    }

    /// Makes a profile, named by the user, and gives it to the space. Its tabs open again signed out.
    private func newProfile(for id: SpaceID) {
        guard let name = prompt("New Profile", message: "The space's tabs open again with their own cookies, logins and site data.", defaultText: ""),
              !name.isEmpty
        else { return }
        let profile = model.sidebar.addProfile(name: name)
        model.sidebar.setProfile(profile, of: id)
    }

    private func rename(_ id: SpaceID) {
        guard let space = document.space(id),
              let text = prompt("Rename Space", defaultText: space.title ?? "")
        else { return }
        model.sidebar.updateSpace(id, title: text.isEmpty ? nil : text, icon: space.icon, theme: space.theme)
    }

    private func changeIcon(_ id: SpaceID) {
        guard let space = document.space(id),
              let text = prompt("Space Icon", message: "An emoji, or the name of an SF Symbol.", defaultText: space.icon ?? "")
        else { return }
        model.sidebar.updateSpace(id, title: space.title, icon: text.isEmpty ? nil : text, theme: space.theme)
    }

    private func setColour(_ colour: RGBAColor, for id: SpaceID) {
        guard let space = document.space(id) else { return }
        model.sidebar.updateSpace(id, title: space.title, icon: space.icon, theme: SpaceTheme(primary: colour))
    }

    private func move(_ id: SpaceID, by offset: Int) {
        guard let index = document.spaces.firstIndex(where: { $0.id == id }) else { return }
        model.sidebar.moveSpace(id, to: index + offset)
    }

    private func delete(_ id: SpaceID) {
        guard let space = document.space(id) else { return }
        let tabCount = document.tabIDs(under: space.pinnedContainerID).count + document.tabIDs(under: space.unpinnedContainerID).count
        if tabCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Delete \(space.title ?? "this space") and its \(tabCount) \(tabCount == 1 ? "tab" : "tabs")?"
            alert.informativeText = "This can't be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        try? model.sidebar.removeSpace(id)
        model.reconcile()
    }

    private func prompt(_ title: String, message: String = "", defaultText: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func swatch(_ colour: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            colour.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

/// A space's button, with a soft square behind the current space. Accepts dropped sidebar items.
final class SpaceButton: NSButton {
    let spaceID: SpaceID
    var onDrop: ((ItemID) -> Void)?
    var isCurrent = false {
        didSet { updateBackground() }
    }

    init(spaceID: SpaceID) {
        self.spaceID = spaceID
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        registerForDraggedTypes([.sidebarItem])
        widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    override var isHighlighted: Bool {
        didSet { updateBackground() }
    }

    private func updateBackground() {
        let alpha: CGFloat = isHighlighted ? 0.16 : isCurrent ? 0.08 : 0
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggedItemID(sender) == nil ? [] : .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = draggedItemID(sender) else { return false }
        onDrop?(id)
        return true
    }
}
