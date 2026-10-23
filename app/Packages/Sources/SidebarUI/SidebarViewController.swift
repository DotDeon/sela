import AppKit
import Browsing
import Favicons
import Sidebar
import SidebarModel

/// The whole sidebar: navigation buttons, the address, favourites, the space pages and the space bar.
@MainActor
public final class SidebarViewController: NSViewController {
    /// Called with what the user typed in the address. Defaults to loading it in the selected tab.
    public var onAddressSubmitted: ((String) -> Void)?

    let pager: SpacePagerView
    let favoritesGrid: FavoritesGridView
    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let tint = NSView()
    private let addressPill = AddressPill()
    private let spaceBar: SpaceBarView
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()

    public init(model: BrowserWindowModel, favicons: FaviconStore) {
        self.model = model
        self.favicons = favicons
        pager = SpacePagerView(model: model, favicons: favicons)
        favoritesGrid = FavoritesGridView(model: model, favicons: favicons)
        spaceBar = SpaceBarView(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState

        tint.wantsLayer = true
        let controls = WindowDragView()
        configure(backButton, symbol: "chevron.left", label: "Back", action: #selector(goBack))
        configure(forwardButton, symbol: "chevron.right", label: "Forward", action: #selector(goForward))
        configure(reloadButton, symbol: "arrow.clockwise", label: "Reload", action: #selector(reloadOrStop))
        let navigation = NSStackView(views: [backButton, forwardButton, reloadButton])
        navigation.spacing = 2

        addressPill.onSubmit = { [weak self] text in self?.submitAddress(text) }
        pager.onNewTab = { [weak self] in self?.newTab() }

        for view in [tint, controls, addressPill, favoritesGrid, pager, spaceBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        navigation.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(navigation)

        let inset: CGFloat = 10
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: background.topAnchor),
            tint.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            controls.topAnchor.constraint(equalTo: background.topAnchor),
            controls.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            controls.heightAnchor.constraint(equalToConstant: 38),
            navigation.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -inset),
            navigation.centerYAnchor.constraint(equalTo: controls.centerYAnchor, constant: 2),

            addressPill.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 4),
            addressPill.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: inset),
            addressPill.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -inset),

            favoritesGrid.topAnchor.constraint(equalTo: addressPill.bottomAnchor, constant: 12),
            favoritesGrid.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: inset),
            favoritesGrid.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -inset),

            pager.topAnchor.constraint(equalTo: favoritesGrid.bottomAnchor, constant: 10),
            pager.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: spaceBar.topAnchor),

            spaceBar.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            spaceBar.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            spaceBar.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -4),
        ])
        view = background
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        keepObserving { [weak self] in self?.update() }
    }

    /// Puts the cursor in the address with the whole address selected.
    public func focusAddress() {
        view.window?.makeFirstResponder(addressPill)
    }

    /// Starts renaming an item in the current space's page.
    public func beginRenaming(_ id: ItemID) {
        pager.pages.first { $0.spaceID == model.selectedSpaceID }?.beginRenaming(id)
    }

    /// Makes a folder at the top of the current space's pinned tabs and starts renaming it.
    public func newFolder() {
        pager.pages.first { $0.spaceID == model.selectedSpaceID }?.newFolder(in: nil)
    }

    private func update() {
        let document = model.sidebar.document
        if let space = document.space(model.selectedSpaceID) {
            tint.layer?.backgroundColor = spaceColor(space, in: document).withAlphaComponent(0.18).cgColor
        }
        let state = model.selectedTab?.state
        addressPill.address = state?.url.map { $0.absoluteString == "about:blank" ? "" : $0.absoluteString } ?? ""
        backButton.isEnabled = state?.canGoBack ?? false
        forwardButton.isEnabled = state?.canGoForward ?? false
        let isLoading = state?.isLoading ?? false
        reloadButton.image = NSImage(systemSymbolName: isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: isLoading ? "Stop" : "Reload")
    }

    private func submitAddress(_ text: String) {
        if let onAddressSubmitted {
            onAddressSubmitted(text)
        } else if let url = AddressInput.resolve(text) {
            model.load(url)
        }
    }

    private func newTab() {
        model.newTab(url: nil)
        focusAddress()
    }

    @objc private func goBack() { model.selectedTab?.goBack() }

    @objc private func goForward() { model.selectedTab?.goForward() }

    @objc private func reloadOrStop() {
        guard let tab = model.selectedTab else { return }
        if tab.state.isLoading { tab.stopLoading() } else { tab.reload() }
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
    }
}

/// Empty space at the top of the sidebar that drags the window, like a title bar.
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
