import AppKit
import BrowserEngine
import Browsing
import Favicons
import Observation
import Sidebar
import SidebarModel

/// The whole sidebar: navigation buttons, the address, favourites, the space pages and the space bar.
@MainActor
public final class SidebarViewController: NSViewController {
    /// Called with what the user typed in the address. Defaults to loading it in the selected tab.
    public var onAddressSubmitted: ((String) -> Void)?
    /// When set, clicking the address calls this instead of editing it in place.
    public var onAddressClicked: (() -> Void)? {
        didSet { addressPill.onClick = onAddressClicked }
    }

    /// Shows or hides the downloads button in the space bar.
    public var showsDownloadsButton: Bool {
        get { !spaceBar.downloadsButton.isHidden }
        set { spaceBar.downloadsButton.isHidden = !newValue }
    }

    /// The downloads button, for anchoring the downloads popover. Its action is `onDownloadsClicked`.
    public var downloadsButton: NSView { spaceBar.downloadsButton }

    public var onDownloadsClicked: (() -> Void)? {
        didSet {
            spaceBar.downloadsButton.target = self
            spaceBar.downloadsButton.action = #selector(downloadsClicked)
        }
    }

    @objc private func downloadsClicked() { onDownloadsClicked?() }

    /// When set, the sidebar's New Tab button calls this instead of adding a blank tab.
    public var onNewTabClicked: (() -> Void)?

    /// The extensions whose buttons show beside back and forward.
    public var extensions: [any BrowserExtension] {
        get { extensionList.items }
        set { extensionList.items = newValue }
    }

    /// Called with the extension whose button was clicked, and the button to show its popup under.
    public var onExtensionClicked: ((any BrowserExtension, NSView) -> Void)? {
        didSet { extensionButtons.onClick = onExtensionClicked }
    }

    /// The extensions menu's Manage Extensions item.
    public var onManageExtensions: (() -> Void)? {
        didSet { extensionButtons.onManage = onManageExtensions }
    }

    /// Where to show an extension's popup: its button, or the extensions menu when its button doesn't fit.
    public func extensionAnchor(for id: String) -> NSView {
        extensionButtons.anchor(for: id)
    }

    let pager: SpacePagerView
    let favoritesGrid: FavoritesGridView
    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let tint = NSView()
    private let addressPill = AddressPill()
    let spaceBar: SpaceBarView
    private let backButton = HoverButton(symbol: "chevron.left", label: "Back", pointSize: 14)
    private let forwardButton = HoverButton(symbol: "chevron.right", label: "Forward", pointSize: 14)
    private let reloadButton = HoverButton(symbol: "arrow.clockwise", label: "Reload")
    /// Sits at the end of the address while the page is an article or shows in reader mode.
    let readerButton = HoverButton(symbol: "doc.plaintext", label: "Show Reader", size: 24)
    private let extensionButtons = ExtensionButtonsView()
    private let extensionList = ExtensionList()

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
        for (button, action) in [(backButton, #selector(goBack)), (forwardButton, #selector(goForward)), (reloadButton, #selector(reloadOrStop))] {
            button.target = self
            button.action = action
        }
        let navigation = NSStackView(views: [backButton, forwardButton, reloadButton])
        navigation.spacing = 0

        addressPill.onSubmit = { [weak self] text in self?.submitAddress(text) }
        pager.onNewTab = { [weak self] in self?.newTab() }
        readerButton.target = self
        readerButton.action = #selector(toggleReader)
        readerButton.isHidden = true

        for view in [tint, controls, addressPill, readerButton, favoritesGrid, pager, spaceBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        navigation.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(navigation)
        extensionButtons.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(extensionButtons)

        let inset: CGFloat = 10
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: background.topAnchor),
            tint.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            controls.topAnchor.constraint(equalTo: background.topAnchor),
            controls.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            // Level with the window's traffic lights.
            controls.heightAnchor.constraint(equalToConstant: 40),
            navigation.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -6),
            navigation.centerYAnchor.constraint(equalTo: controls.centerYAnchor, constant: 1),
            extensionButtons.trailingAnchor.constraint(equalTo: navigation.leadingAnchor, constant: -2),
            extensionButtons.centerYAnchor.constraint(equalTo: navigation.centerYAnchor),
            // Clear of the window's traffic lights. Buttons that don't fit move to the extensions menu.
            extensionButtons.leadingAnchor.constraint(greaterThanOrEqualTo: controls.leadingAnchor, constant: 78),

            addressPill.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 2),
            addressPill.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: inset),
            addressPill.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -inset),
            readerButton.trailingAnchor.constraint(equalTo: addressPill.trailingAnchor, constant: -5),
            readerButton.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),

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
        keepObserving { [weak self] in self?.updateExtensionButtons() }
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
        reloadButton.setSymbol(isLoading ? "xmark" : "arrow.clockwise", label: isLoading ? "Stop" : "Reload")
        updateReaderButton(state)
    }

    private func updateReaderButton(_ state: TabState?) {
        let isShowing = state?.isShowingReader ?? false
        let isOffered = isShowing || (state?.isReaderAvailable ?? false)
        readerButton.isHidden = !isOffered
        addressPill.trailingInset = isOffered ? 22 : 0
        let label = isShowing ? "Hide Reader" : "Show Reader"
        readerButton.setSymbol(isShowing ? "doc.plaintext.fill" : "doc.plaintext", label: label)
        readerButton.toolTip = label
        readerButton.contentTintColor = isShowing ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func toggleReader() {
        Task { await model.toggleReader() }
    }

    /// Reads each extension's button for the selected tab, so an extension changing it updates the sidebar.
    private func updateExtensionButtons() {
        extensionButtons.update(extensions: extensionList.items, tab: model.selectedTab)
    }

    private func submitAddress(_ text: String) {
        if let onAddressSubmitted {
            onAddressSubmitted(text)
        } else if let url = AddressInput.resolve(text) {
            model.load(url)
        }
    }

    private func newTab() {
        if let onNewTabClicked {
            onNewTabClicked()
            return
        }
        model.newTab(url: nil)
        focusAddress()
    }

    @objc private func goBack() { model.selectedTab?.goBack() }

    @objc private func goForward() { model.selectedTab?.goForward() }

    @objc private func reloadOrStop() {
        guard let tab = model.selectedTab else { return }
        if tab.state.isLoading { tab.stopLoading() } else { tab.reload() }
    }
}

/// The extensions the sidebar shows buttons for, observable so a new list redraws them.
@MainActor
@Observable
private final class ExtensionList {
    var items: [any BrowserExtension] = []
}

/// Empty space at the top of the sidebar that drags the window, like a title bar.
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
