import AppKit
import BrowserEngine
import Browsing

/// One browser window: a temporary tab list, the page, and a toolbar with the address field.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let model: BrowserWindowModel
    var onClose: (() -> Void)?

    private let addressField = NSTextField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private var dialogPresenter: DialogPresenter?

    init(engine: any BrowserEngine) {
        model = BrowserWindowModel(engine: engine)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let split = NSSplitViewController()
        let tabList = NSSplitViewItem(sidebarWithViewController: TabListViewController(model: model))
        tabList.minimumThickness = 180
        tabList.maximumThickness = 360
        split.addSplitViewItem(tabList)
        split.addSplitViewItem(NSSplitViewItem(viewController: WebContentViewController(model: model)))
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.center()
        window.setFrameAutosaveName("BrowserWindow")
        window.delegate = self
        window.toolbarStyle = .unified
        window.toolbar = makeToolbar()

        dialogPresenter = DialogPresenter(model: model, window: window)
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Actions

    @objc func newTab(_ sender: Any?) {
        model.openTab(url: nil)
        focusAddressBar(nil)
    }

    @objc func focusAddressBar(_ sender: Any?) {
        window?.makeFirstResponder(addressField)
    }

    @objc func closeTab(_ sender: Any?) {
        if let id = model.selectedTabID {
            model.close(id)
        } else {
            window?.performClose(nil)
        }
    }

    @objc func reloadTab(_ sender: Any?) { model.selectedTab?.reload() }

    @objc func stopTab(_ sender: Any?) { model.selectedTab?.stopLoading() }

    @objc func reloadOrStop(_ sender: Any?) {
        guard let tab = model.selectedTab else { return }
        if tab.state.isLoading { tab.stopLoading() } else { tab.reload() }
    }

    @objc func goBackInTab(_ sender: Any?) { model.selectedTab?.goBack() }

    @objc func goForwardInTab(_ sender: Any?) { model.selectedTab?.goForward() }

    @objc func selectNextTab(_ sender: Any?) { model.selectNext() }

    @objc func selectPreviousTab(_ sender: Any?) { model.selectPrevious() }

    @objc func selectTabByNumber(_ sender: NSMenuItem) { model.select(number: sender.tag) }

    @objc private func addressSubmitted(_ sender: NSTextField) {
        guard let url = AddressInput.resolve(sender.stringValue) else { return }
        if let tab = model.selectedTab {
            tab.load(url)
        } else {
            model.openTab(url: url)
        }
        if let content = model.selectedTab?.contentView {
            window?.makeFirstResponder(content)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        for tab in model.tabs {
            model.close(tab.id)
        }
        onClose?()
    }

    // MARK: Updates

    private func update() {
        let state = model.selectedTab?.state
        window?.title = state.map(displayTitle(for:)) ?? "Brow"
        backButton.isEnabled = state?.canGoBack ?? false
        forwardButton.isEnabled = state?.canGoForward ?? false
        let isLoading = state?.isLoading ?? false
        reloadButton.image = NSImage(systemSymbolName: isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: isLoading ? "Stop" : "Reload")
        if addressField.currentEditor() == nil {
            let url = state?.url?.absoluteString
            addressField.stringValue = url == "about:blank" ? "" : url ?? ""
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BrowserToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    fileprivate func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.target = self
        button.action = action
        button.toolTip = label
    }
}

extension NSToolbarItem.Identifier {
    fileprivate static let back = Self("back")
    fileprivate static let forward = Self("forward")
    fileprivate static let reload = Self("reload")
    fileprivate static let address = Self("address")
}

extension BrowserWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .reload, .address]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case .back:
            configure(backButton, symbol: "chevron.left", label: "Back", action: #selector(goBackInTab(_:)))
            item.view = backButton
            item.label = "Back"
        case .forward:
            configure(forwardButton, symbol: "chevron.right", label: "Forward", action: #selector(goForwardInTab(_:)))
            item.view = forwardButton
            item.label = "Forward"
        case .reload:
            configure(reloadButton, symbol: "arrow.clockwise", label: "Reload", action: #selector(reloadOrStop(_:)))
            item.view = reloadButton
            item.label = "Reload"
        case .address:
            addressField.placeholderString = "Search or enter address"
            addressField.lineBreakMode = .byTruncatingTail
            addressField.usesSingleLineMode = true
            addressField.cell?.sendsActionOnEndEditing = false
            addressField.target = self
            addressField.action = #selector(addressSubmitted(_:))
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
            let preferred = addressField.widthAnchor.constraint(equalToConstant: 2000)
            preferred.priority = .defaultLow
            preferred.isActive = true
            item.view = addressField
            item.label = "Address"
            item.visibilityPriority = .high
        default:
            return nil
        }
        return item
    }
}
