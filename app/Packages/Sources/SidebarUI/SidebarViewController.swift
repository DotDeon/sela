import AppKit
import BrowserEngine
import Browsing
import Favicons
import Observation
import PageTranslation
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

    /// The button that hides the sidebar, or docks it again while it's hidden and slid out.
    public var onToggleSidebarClicked: (() -> Void)?
    @objc private func toggleSidebarClicked() { onToggleSidebarClicked?() }

    /// Names the sidebar button for what a click does now.
    public func showSidebarHidden(_ hidden: Bool) {
        let label = hidden ? "Keep Sidebar Open" : "Hide Sidebar"
        sidebarButton.setSymbol("sidebar.left", label: label, pointSize: 14)
        sidebarButton.toolTip = label
    }

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
    private let sidebarButton = HoverButton(symbol: "sidebar.left", label: "Hide Sidebar", pointSize: 14)
    private let backButton = HoverButton(symbol: "chevron.left", label: "Back", pointSize: 14)
    private let forwardButton = HoverButton(symbol: "chevron.right", label: "Forward", pointSize: 14)
    private let reloadButton = HoverButton(symbol: "arrow.clockwise", label: "Reload")
    /// Sits at the end of the address while the page is an article or shows in reader mode.
    let readerButton = HoverButton(symbol: "doc.plaintext", label: "Show Reader", size: 24)
    /// The zoom level, at the end of the address while the page isn't at actual size. A click goes back to it.
    let zoomButton = NSButton(title: "", target: nil, action: nil)
    /// Sits before the reader button while the page is in a language the user doesn't read, or is translated.
    let translateButton = HoverButton(symbol: "translate", label: "Translate Page", size: 24)
    /// Fills in over the translate button's symbol while a page translates.
    private let translateProgress = NSProgressIndicator()
    /// The buttons at the end of the address, in the order they sit.
    private let addressButtons = NSStackView()
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
        for (button, action) in [(sidebarButton, #selector(toggleSidebarClicked)), (backButton, #selector(goBack)), (forwardButton, #selector(goForward)), (reloadButton, #selector(reloadOrStop))] {
            button.target = self
            button.action = action
        }
        let navigation = NSStackView(views: [sidebarButton, backButton, forwardButton, reloadButton])
        navigation.spacing = 0

        addressPill.onSubmit = { [weak self] text in self?.submitAddress(text) }
        pager.onNewTab = { [weak self] in self?.newTab() }
        readerButton.target = self
        readerButton.action = #selector(toggleReader)
        readerButton.isHidden = true
        zoomButton.bezelStyle = .inline
        zoomButton.isBordered = false
        zoomButton.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomButton.contentTintColor = .secondaryLabelColor
        zoomButton.toolTip = "Back to Actual Size"
        zoomButton.target = self
        zoomButton.action = #selector(resetZoom)
        zoomButton.isHidden = true
        translateButton.target = self
        translateButton.action = #selector(translateClicked)
        translateButton.isHidden = true
        translateProgress.style = .spinning
        translateProgress.controlSize = .small
        translateProgress.isIndeterminate = false
        translateProgress.minValue = 0
        translateProgress.maxValue = 1
        translateProgress.isHidden = true
        translateProgress.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addSubview(translateProgress)
        addressButtons.orientation = .horizontal
        addressButtons.spacing = 0
        addressButtons.addArrangedSubview(zoomButton)
        addressButtons.addArrangedSubview(translateButton)
        addressButtons.addArrangedSubview(readerButton)

        for view in [tint, controls, addressPill, addressButtons, favoritesGrid, pager, spaceBar] {
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
            addressButtons.trailingAnchor.constraint(equalTo: addressPill.trailingAnchor, constant: -5),
            addressButtons.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),
            translateProgress.centerXAnchor.constraint(equalTo: translateButton.centerXAnchor),
            translateProgress.centerYAnchor.constraint(equalTo: translateButton.centerYAnchor),

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
        // A new symbol image only when loading starts or stops, not on every title or address change.
        if isLoading != showsStop {
            showsStop = isLoading
            reloadButton.setSymbol(isLoading ? "xmark" : "arrow.clockwise", label: isLoading ? "Stop" : "Reload")
        }
        updateReaderButton(state)
        updateZoomButton(state)
        updateTranslateButton(model.selectedTranslator)
    }

    private var showsStop = false

    private var readerShown: (offered: Bool, showing: Bool)?

    private func updateReaderButton(_ state: TabState?) {
        let isShowing = state?.isShowingReader ?? false
        let isOffered = isShowing || (state?.isReaderAvailable ?? false)
        guard readerShown?.offered != isOffered || readerShown?.showing != isShowing else { return }
        readerShown = (isOffered, isShowing)
        readerButton.isHidden = !isOffered
        updateAddressInset()
        let label = isShowing ? "Hide Reader" : "Show Reader"
        readerButton.setSymbol(isShowing ? "doc.plaintext.fill" : "doc.plaintext", label: label)
        readerButton.toolTip = label
        readerButton.contentTintColor = isShowing ? .controlAccentColor : .secondaryLabelColor
        updateAddressInset()
    }

    private var shownZoom: String?

    private func updateZoomButton(_ state: TabState?) {
        let zoom = state?.pageZoom ?? 1
        let text = PageZoom.isActualSize(zoom) ? nil : PageZoom.percentText(zoom)
        guard text != shownZoom else { return }
        shownZoom = text
        zoomButton.isHidden = text == nil
        zoomButton.title = text ?? ""
        zoomButton.setAccessibilityLabel(text.map { "Zoomed to \($0). Back to Actual Size" })
        updateAddressInset()
    }

    @objc private func toggleReader() {
        Task { await model.toggleReader() }
    }

    @objc private func resetZoom() {
        model.resetZoom()
    }

    /// Leaves room at the end of the address for whichever of the zoom level, translate and reader buttons show.
    private func updateAddressInset() {
        let shown = addressButtons.arrangedSubviews.filter { !$0.isHidden }
        guard !shown.isEmpty else {
            addressPill.trailingInset = 0
            return
        }
        let widths = shown.map { $0.fittingSize.width }.reduce(0, +)
        addressPill.trailingInset = widths + CGFloat(shown.count - 1) * addressButtons.spacing + 4
    }

    /// Called with the translate button when it's clicked. The window decides what to show.
    public var onTranslateClicked: ((NSView) -> Void)?

    /// Where notes about translation point: the translate button, or the address when the button isn't showing.
    public var translationAnchor: NSView {
        translateButton.isHidden ? addressPill : translateButton
    }

    private var translateShown: (offered: Bool, status: PageTranslator.Status)?

    /// Shows the button while the page is offered for translation, or has been translated; a progress wheel takes
    /// the symbol's place while it translates.
    private func updateTranslateButton(_ translator: PageTranslator?) {
        let status = translator?.status ?? .idle
        let isOffered = translator.map { $0.isOffered || $0.status.isActive } ?? false
        guard translateShown?.offered != isOffered || translateShown?.status != status else { return }
        translateShown = (isOffered, status)
        translateButton.isHidden = !isOffered
        updateAddressInset()
        let label: String
        switch status {
        case .translated: label = "Show Original"
        case .checking, .downloading, .translating: label = "Translating"
        case .idle, .unsupported, .downloadNeeded, .failed: label = "Translate Page"
        }
        if case .translating(let fraction) = status {
            translateProgress.doubleValue = max(fraction, 0.05)
        } else {
            translateProgress.doubleValue = 0.05
        }
        translateProgress.isHidden = !status.isBusy
        if status.isBusy {
            translateButton.image = nil
            translateButton.setAccessibilityLabel(label)
        } else {
            translateButton.setSymbol("translate", label: label)
        }
        translateButton.toolTip = label
        translateButton.contentTintColor = status.isActive ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func translateClicked() {
        onTranslateClicked?(translateButton)
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
