import AppKit
import Archive
import BrowserEngine
import Browsing
import ContentBlocking
import Downloads
import History
import SidebarUI

/// Little Sela: a small window for a link another app opened, with a slim title bar showing the page's title
/// and site, back, forward and reload, and Open in Sela, which moves the page to a main window's tabs.
/// Closing the window closes the page, and it goes to the archive like a closed unpinned tab.
@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSTextFieldDelegate {
    static let titleBarHeight: CGFloat = 38
    /// Room for the close, minimise and zoom buttons at the left of the title bar.
    static let windowButtonsWidth: CGFloat = 78

    let model: LittleWindowModel
    /// Gets the live page when the user chooses Open in Sela. The window closes straight after.
    var onOpenInSela: ((any BrowserTab) -> Void)?
    var onClose: (() -> Void)?

    private let contentBlocker: ContentBlocker?
    private let card = PageCardView(frame: .zero)
    private let pageArea = NSView()
    private let backButton = HoverButton(symbol: "chevron.left", label: "Back")
    private let forwardButton = HoverButton(symbol: "chevron.right", label: "Forward")
    private let reloadButton = HoverButton(symbol: "arrow.clockwise", label: "Reload Page", pointSize: 12)
    private let titleArea = TitleArea()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hostLabel = NSTextField(labelWithString: "")
    private let addressField = NSTextField()
    private var dialogPresenter: DialogPresenter?
    private var findBar: FindBarController?

    /// A window showing `url`, or an empty one with the address field ready when `url` is nil.
    /// It opens clear of the frames in `occupied`, the other Little Sela windows.
    init(engine: any BrowserEngine, url: URL?, archive: ArchiveStore?, history: HistoryStore?, contentBlocker: ContentBlocker?,
         downloads: DownloadList, occupied: [CGRect]) {
        model = LittleWindowModel(engine: engine, url: url, archive: archive, downloads: downloads)
        self.contentBlocker = contentBlocker
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = LittleWindowFrame().frameForNewWindow(visible: visible, occupied: occupied)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = LittleWindowFrame.minimumSize
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.contentView = makeContent()
        window.setFrame(frame, display: false)
        window.delegate = self

        dialogPresenter = DialogPresenter(model: model, window: window)
        findBar = FindBarController(model: model, host: pageArea)
        model.onPageVisited = { [weak history] url, title in history?.recordVisit(url: url, title: title) }
        model.onChooseFiles = { [weak self] multiple, folders in await PagePrompts.chooseFiles(in: self?.window, multiple: multiple, folders: folders) }
        model.onCaptureRequest = { [weak self] media, origin in await PagePrompts.askToCapture(media, origin: origin, in: self?.window) }
        model.onCloseRequest = { [weak self] in self?.window?.performClose(nil) }
        card.show(model.tab?.contentView)
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window in front, with the page focused, or the address field when there's no page yet.
    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if model.tab?.state.url == nil {
            focusAddressBar(nil)
        } else if let page = model.tab?.contentView {
            window?.makeFirstResponder(page)
        }
    }

    // MARK: Layout

    private func makeContent() -> NSView {
        let root = NSVisualEffectView()
        root.material = .titlebar
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState

        backButton.target = self
        backButton.action = #selector(goBackInTab(_:))
        forwardButton.target = self
        forwardButton.action = #selector(goForwardInTab(_:))
        reloadButton.target = self
        reloadButton.action = #selector(reloadOrStop)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostLabel.font = .systemFont(ofSize: 12)
        hostLabel.textColor = .secondaryLabelColor
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        let titles = NSStackView(views: [titleLabel, hostLabel])
        titles.spacing = 6
        titles.translatesAutoresizingMaskIntoConstraints = false
        titleArea.addSubview(titles)
        titleArea.onClick = { [weak self] in self?.focusAddressBar(nil) }
        titleArea.toolTip = "Click to change the address"

        addressField.placeholderString = "Search or enter address"
        addressField.font = .systemFont(ofSize: 12)
        addressField.bezelStyle = .roundedBezel
        addressField.focusRingType = .none
        addressField.delegate = self
        addressField.target = self
        addressField.action = #selector(addressSubmitted)
        addressField.isHidden = true
        addressField.cell?.lineBreakMode = .byTruncatingTail

        let openButton = NSButton(title: "Open in Sela", target: self, action: #selector(openInSela(_:)))
        openButton.bezelStyle = .push
        openButton.controlSize = .small
        openButton.font = .systemFont(ofSize: 11)
        openButton.toolTip = "Move this page to your tabs"

        let controls = NSStackView(views: [backButton, forwardButton, reloadButton])
        controls.spacing = 2
        card.cornerRadius = 8
        for view in [controls, titleArea, addressField, openButton, pageArea] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        pageArea.addSubview(card)

        let bar = Self.titleBarHeight
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.windowButtonsWidth),
            controls.centerYAnchor.constraint(equalTo: root.topAnchor, constant: bar / 2),

            titleArea.leadingAnchor.constraint(equalTo: controls.trailingAnchor, constant: 8),
            titleArea.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            titleArea.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            titleArea.heightAnchor.constraint(equalToConstant: bar - 12),
            titles.leadingAnchor.constraint(equalTo: titleArea.leadingAnchor, constant: 6),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: titleArea.trailingAnchor, constant: -6),
            titles.centerYAnchor.constraint(equalTo: titleArea.centerYAnchor),

            addressField.leadingAnchor.constraint(equalTo: titleArea.leadingAnchor),
            addressField.trailingAnchor.constraint(equalTo: titleArea.trailingAnchor),
            addressField.centerYAnchor.constraint(equalTo: titleArea.centerYAnchor),

            openButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            openButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),

            pageArea.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            pageArea.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            pageArea.topAnchor.constraint(equalTo: root.topAnchor, constant: bar),
            pageArea.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            card.leadingAnchor.constraint(equalTo: pageArea.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: pageArea.trailingAnchor),
            card.topAnchor.constraint(equalTo: pageArea.topAnchor),
            card.bottomAnchor.constraint(equalTo: pageArea.bottomAnchor),
        ])
        return root
    }

    private func update() {
        let state = model.tab?.state ?? .blank
        let host = state.url.flatMap { $0.isFileURL ? nil : $0.host() }.map(Self.withoutWWW)
        let title = displayTitle(for: state)
        titleLabel.stringValue = title
        // The host repeats when the page has no title of its own.
        hostLabel.stringValue = host == title ? "" : host ?? ""
        hostLabel.isHidden = hostLabel.stringValue.isEmpty
        backButton.isEnabled = state.canGoBack
        forwardButton.isEnabled = state.canGoForward
        reloadButton.setSymbol(state.isLoading ? "xmark" : "arrow.clockwise", label: state.isLoading ? "Stop" : "Reload Page", pointSize: 12)
        reloadButton.toolTip = state.isLoading ? "Stop" : "Reload Page"
        reloadButton.isEnabled = state.url != nil
        // Hidden in the title bar, but the Window menu and Mission Control use it.
        window?.title = state.url == nil ? "Little Sela" : title
    }

    private static func withoutWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Address

    @objc func focusAddressBar(_ sender: Any?) {
        let url = model.tab?.state.url?.absoluteString ?? ""
        addressField.stringValue = url == "about:blank" ? "" : url
        addressField.isHidden = false
        titleArea.isHidden = true
        window?.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    private func endAddressEditing() {
        guard !addressField.isHidden else { return }
        // An empty window keeps the field, so there's somewhere to type.
        guard model.tab?.state.url != nil else { return }
        addressField.isHidden = true
        titleArea.isHidden = false
    }

    @objc private func addressSubmitted() {
        guard let url = AddressInput.resolve(addressField.stringValue) else { return }
        model.load(url)
        addressField.isHidden = true
        titleArea.isHidden = false
        if let page = model.tab?.contentView { window?.makeFirstResponder(page) }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endAddressEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if model.tab?.state.url == nil {
            window?.performClose(nil)
        } else if let page = model.tab?.contentView {
            window?.makeFirstResponder(page)
        }
        return true
    }

    // MARK: Actions

    /// Moves the page, live and with its history, to a main window's tabs, and closes this window.
    @objc func openInSela(_ sender: Any?) {
        guard model.tab?.state.url != nil else { return }
        card.show(nil)
        guard let tab = model.takeTab() else { return }
        onOpenInSela?(tab)
        window?.close()
    }

    @objc private func reloadOrStop() {
        if model.tab?.state.isLoading == true { stopTab(nil) } else { reloadTab(nil) }
    }

    /// Cmd+W closes the window, since it holds one page.
    @objc func closeTab(_ sender: Any?) { window?.performClose(nil) }

    @objc func reloadTab(_ sender: Any?) { model.tab?.reload() }

    @objc func stopTab(_ sender: Any?) { model.tab?.stopLoading() }

    @objc func goBackInTab(_ sender: Any?) { model.tab?.goBack() }

    @objc func goForwardInTab(_ sender: Any?) { model.tab?.goForward() }

    @objc func showFindBar(_ sender: Any?) { findBar?.show() }

    @objc func findNextInPage(_ sender: Any?) { findBar?.findNext() }

    @objc func findPreviousInPage(_ sender: Any?) { findBar?.findPrevious() }

    @objc func copyURL(_ sender: Any?) {
        guard let url = model.tab?.state.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Tab > Block Ads on This Site. Reloads the page so the change shows at once.
    @objc func toggleSiteBlocking(_ sender: Any?) {
        guard let contentBlocker, let url = blockableURL else { return }
        contentBlocker.setBlocking(!contentBlocker.isBlocking(on: url), forSiteOf: url)
        model.tab?.reload()
    }

    private var blockableURL: URL? {
        guard contentBlocker?.isEnabled == true, let url = model.tab?.state.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(openInSela(_:)), #selector(copyURL(_:)), #selector(reloadTab(_:)):
            return model.tab?.state.url != nil
        case #selector(goBackInTab(_:)):
            return model.tab?.state.canGoBack == true
        case #selector(goForwardInTab(_:)):
            return model.tab?.state.canGoForward == true
        case #selector(toggleSiteBlocking(_:)):
            guard let url = blockableURL, let contentBlocker else {
                item.state = .off
                return false
            }
            item.state = contentBlocker.isBlocking(on: url) ? .on : .off
            return true
        default:
            return true
        }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { rememberFrame() }

    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }

    func windowWillClose(_ notification: Notification) {
        rememberFrame()
        // After Open in Sela the model holds no page, so nothing is closed or archived.
        model.close()
        onClose?()
    }

    private func rememberFrame() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        LittleWindowFrame().saved = window.frame
    }
}

/// The page's title and site in the title bar. A click on it edits the address.
private final class TitleArea: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    // Clicks belong here, not to the window's title bar, which would start a drag.
    override var mouseDownCanMoveWindow: Bool { false }
}
