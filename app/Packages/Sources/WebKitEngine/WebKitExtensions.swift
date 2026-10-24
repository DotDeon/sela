import AppKit
import BrowserEngine
import WebKit

/// The one `WKWebExtensionController` every web view shares, and what it asks of Sela's windows and tabs.
@available(macOS 15.4, *)
@MainActor
final class WebKitExtensions: NSObject, WKWebExtensionControllerDelegate {
    let controller: WKWebExtensionController
    private unowned let engine: WebKitEngine
    private var loaded: [String: WebKitExtension] = [:]
    /// Each Sela window's stand-in, kept so WebKit sees the same object every time.
    private var windows: [ObjectIdentifier: WebKitExtensionWindow] = [:]
    /// Tabs WebKit has been told about, so it only hears of closing the ones it knows.
    private var announcedTabs: Set<ObjectIdentifier> = []
    private var permissionObservers: [String: [NSObjectProtocol]] = [:]
    /// The button the user just clicked, for the popup that click opens.
    private var pendingAnchor: NSView?

    init(engine: WebKitEngine, persistent: Bool, dataStore: WKWebsiteDataStore) {
        self.engine = engine
        let configuration: WKWebExtensionController.Configuration = persistent ? .default() : .nonPersistent()
        configuration.defaultWebsiteDataStore = dataStore
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    private var host: (any ExtensionHost)? { engine.extensionHost }

    // MARK: Loading

    func read(at folder: URL) async throws -> ExtensionDetails {
        Self.details(of: try await WKWebExtension(resourceBaseURL: folder))
    }

    func load(id: String, at folder: URL, permissions: ExtensionPermissions) async throws -> WebKitExtension {
        unload(id: id)
        let webExtension = try await WKWebExtension(resourceBaseURL: folder)
        let context = WKWebExtensionContext(for: webExtension)
        // The same identifier and address every launch, so the extension finds the data it saved.
        context.uniqueIdentifier = id
        if let baseURL = URL(string: "webkit-extension://\(id)/") { context.baseURL = baseURL }
        context.isInspectable = true
        context.grantedPermissions = Self.permissionDates(permissions.granted)
        context.deniedPermissions = Self.permissionDates(permissions.denied)
        context.grantedPermissionMatchPatterns = Self.patternDates(permissions.grantedMatchPatterns)
        context.deniedPermissionMatchPatterns = Self.patternDates(permissions.deniedMatchPatterns)
        try controller.load(context)

        let loadedExtension = WebKitExtension(id: id, context: context)
        loaded[id] = loadedExtension
        observePermissions(of: loadedExtension)
        return loadedExtension
    }

    func unload(id: String) {
        guard let loadedExtension = loaded.removeValue(forKey: id) else { return }
        for observer in permissionObservers.removeValue(forKey: id) ?? [] {
            NotificationCenter.default.removeObserver(observer)
        }
        try? controller.unload(loadedExtension.context)
    }

    /// The configuration for a page at one of an extension's own addresses, or nil for any other page.
    func webViewConfiguration(for url: URL) -> WKWebViewConfiguration? {
        controller.extensionContext(for: url)?.webViewConfiguration
    }

    private func observePermissions(of loadedExtension: WebKitExtension) {
        let names: [Notification.Name] = [
            WKWebExtensionContext.permissionsWereGrantedNotification,
            WKWebExtensionContext.permissionsWereDeniedNotification,
            WKWebExtensionContext.grantedPermissionsWereRemovedNotification,
            WKWebExtensionContext.deniedPermissionsWereRemovedNotification,
            WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification,
            WKWebExtensionContext.permissionMatchPatternsWereDeniedNotification,
            WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification,
            WKWebExtensionContext.deniedPermissionMatchPatternsWereRemovedNotification,
        ]
        let id = loadedExtension.id
        permissionObservers[id] = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: loadedExtension.context, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let current = self.loaded[id] else { return }
                    self.engine.onExtensionPermissionsChanged?(id, current.permissions)
                }
            }
        }
    }

    // MARK: Actions

    func performAction(of id: String, in tab: WebKitTab?, anchor: NSView) {
        guard let loadedExtension = loaded[id] else { return }
        pendingAnchor = anchor
        loadedExtension.context.performAction(for: tab)
        // A click on an extension without a popup never asks to present one.
        DispatchQueue.main.async { [weak self] in self?.pendingAnchor = nil }
    }

    // MARK: Windows and tabs

    func window(for window: any ExtensionWindow) -> WebKitExtensionWindow {
        let key = ObjectIdentifier(window)
        if let existing = windows[key] { return existing }
        let made = WebKitExtensionWindow(window: window)
        windows[key] = made
        return made
    }

    /// The window showing `tab`, or nil when it's in none, as with Peek.
    func window(containing tab: WebKitTab) -> WebKitExtensionWindow? {
        guard let window = host?.extensionWindows.first(where: { $0.extensionTabs.contains { $0 === tab } }) else { return nil }
        return self.window(for: window)
    }

    func windowDidOpen(_ window: any ExtensionWindow) {
        controller.didOpenWindow(self.window(for: window))
    }

    func windowDidClose(_ window: any ExtensionWindow) {
        guard let made = windows.removeValue(forKey: ObjectIdentifier(window)) else { return }
        for tab in window.extensionTabs.compactMap({ $0 as? WebKitTab }) where announcedTabs.remove(ObjectIdentifier(tab)) != nil {
            controller.didCloseTab(tab, windowIsClosing: true)
        }
        controller.didCloseWindow(made)
    }

    func windowDidFocus(_ window: (any ExtensionWindow)?) {
        controller.didFocusWindow(window.map { self.window(for: $0) })
    }

    /// Announced on the next turn of the run loop, once the window has put the tab in its sidebar.
    func tabDidOpen(_ tab: WebKitTab) {
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab, !tab.isClosed else { return }
            announcedTabs.insert(ObjectIdentifier(tab))
            controller.didOpenTab(tab)
            // A new tab is often selected before WebKit hears of it, so its activation is passed on now.
            if window(containing: tab)?.window?.activeExtensionTab === tab {
                controller.didActivateTab(tab, previousActiveTab: nil)
            }
        }
    }

    func tabDidClose(_ tab: WebKitTab) {
        guard announcedTabs.remove(ObjectIdentifier(tab)) != nil else { return }
        controller.didCloseTab(tab, windowIsClosing: false)
    }

    func tabDidActivate(_ tab: WebKitTab, previous: WebKitTab?) {
        guard announcedTabs.contains(ObjectIdentifier(tab)) else { return }
        let known = previous.flatMap { announcedTabs.contains(ObjectIdentifier($0)) ? $0 : nil }
        controller.didActivateTab(tab, previousActiveTab: known)
    }

    func tabStateDidChange(_ tab: WebKitTab, from previous: TabState) {
        guard announcedTabs.contains(ObjectIdentifier(tab)) else { return }
        var changed: WKWebExtension.TabChangedProperties = []
        if tab.state.url != previous.url { changed.insert(.URL) }
        if tab.state.title != previous.title { changed.insert(.title) }
        if tab.state.isLoading != previous.isLoading { changed.insert(.loading) }
        if !changed.isEmpty { controller.didChangeTabProperties(changed, for: tab) }
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        (host?.extensionWindows ?? []).map { window(for: $0) }
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        host?.focusedExtensionWindow.map { window(for: $0) }
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        let target = (configuration.window as? WebKitExtensionWindow)?.window
        guard let tab = host?.openTab(url: configuration.url, in: target, active: configuration.shouldBeActive, pinned: configuration.shouldBePinned) as? WebKitTab
        else { throw ExtensionRequestFailed(message: "Sela couldn't open a tab.") }
        return tab
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        guard let made = host?.openWindow(urls: configuration.tabURLs, focused: configuration.shouldBeFocused)
        else { throw ExtensionRequestFailed(message: "Sela couldn't open a window.") }
        return window(for: made)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        guard let url = extensionContext.optionsPageURL, host?.openTab(url: url, in: nil, active: true, pinned: false) != nil
        else { throw ExtensionRequestFailed(message: "This extension has no options page.") }
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        let allowed = await ask(extensionContext, permissions: Set(permissions.map(\.rawValue)), matchPatterns: [])
        return (allowed ? permissions : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        let patterns = Set(urls.compactMap { $0.host().map { "*://\($0)/*" } })
        let allowed = await ask(extensionContext, permissions: [], matchPatterns: patterns)
        return (allowed ? urls : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let allowed = await ask(extensionContext, permissions: [], matchPatterns: Set(matchPatterns.map(\.string)))
        return (allowed ? matchPatterns : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        loaded[context.uniqueIdentifier]?.actionDidChange()
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext) async throws {
        let anchor = pendingAnchor ?? host?.actionAnchor(forExtension: context.uniqueIdentifier)
        pendingAnchor = nil
        guard let popover = action.popupPopover, let anchor, anchor.window != nil
        else { throw ExtensionRequestFailed(message: "There's nowhere to show the popup.") }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }

    private func ask(_ context: WKWebExtensionContext, permissions: Set<String>, matchPatterns: Set<String>) async -> Bool {
        guard let host else { return false }
        let name = context.webExtension.displayName ?? "An extension"
        return await host.askPermission(extensionName: name, permissions: permissions, matchPatterns: matchPatterns)
    }

    // MARK: Conversions

    static func details(of webExtension: WKWebExtension) -> ExtensionDetails {
        ExtensionDetails(
            name: webExtension.displayName ?? webExtension.displayShortName ?? "Unnamed extension",
            version: webExtension.displayVersion ?? webExtension.version,
            summary: webExtension.displayDescription,
            requestedPermissions: Set(webExtension.requestedPermissions.map(\.rawValue)),
            // Includes the sites its content scripts run on, which it needs access to as well.
            requestedMatchPatterns: Set(webExtension.allRequestedMatchPatterns.map(\.string))
        )
    }

    static func permissionDates(_ dates: [String: Date]) -> [WKWebExtension.Permission: Date] {
        Dictionary(dates.map { (WKWebExtension.Permission(rawValue: $0.key), $0.value) }, uniquingKeysWith: max)
    }

    static func patternDates(_ dates: [String: Date]) -> [WKWebExtension.MatchPattern: Date] {
        Dictionary(dates.compactMap { entry in (try? WKWebExtension.MatchPattern(string: entry.key)).map { ($0, entry.value) } }, uniquingKeysWith: max)
    }
}

struct ExtensionRequestFailed: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// An extension WebKit is running, as Sela's UI sees it.
@available(macOS 15.4, *)
@MainActor
@Observable
final class WebKitExtension: BrowserExtension {
    let id: String
    @ObservationIgnored let context: WKWebExtensionContext
    /// Goes up each time the extension changes its button, so views reading `action(for:)` update.
    private var actionRevision = 0
    private var permissionRevision = 0

    init(id: String, context: WKWebExtensionContext) {
        self.id = id
        self.context = context
    }

    var details: ExtensionDetails { WebKitExtensions.details(of: context.webExtension) }

    var permissions: ExtensionPermissions {
        func strings<Key>(_ dates: [Key: Date], _ name: (Key) -> String) -> [String: Date] {
            Dictionary(dates.map { (name($0.key), $0.value) }, uniquingKeysWith: max)
        }
        return ExtensionPermissions(
            granted: strings(context.grantedPermissions) { $0.rawValue },
            denied: strings(context.deniedPermissions) { $0.rawValue },
            grantedMatchPatterns: strings(context.grantedPermissionMatchPatterns) { $0.string },
            deniedMatchPatterns: strings(context.deniedPermissionMatchPatterns) { $0.string }
        )
    }

    var optionsPageURL: URL? { context.optionsPageURL }

    func icon(size: CGFloat) -> NSImage? {
        context.webExtension.icon(for: CGSize(width: size, height: size))
    }

    func action(for tab: (any BrowserTab)?) -> ExtensionActionState? {
        _ = actionRevision
        guard let action = context.action(for: tab as? WebKitTab) else { return nil }
        return ExtensionActionState(
            label: action.label,
            badgeText: action.badgeText,
            icon: action.icon(for: CGSize(width: 16, height: 16)) ?? icon(size: 16),
            isEnabled: action.isEnabled
        )
    }

    func actionDidChange() {
        actionRevision += 1
    }
}

/// A Sela window as WebKit's extension APIs see it.
@available(macOS 15.4, *)
@MainActor
final class WebKitExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var window: (any ExtensionWindow)?

    init(window: any ExtensionWindow) {
        self.window = window
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        window?.extensionTabs.compactMap { $0 as? WebKitTab } ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        window?.activeExtensionTab as? WebKitTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMinimized { return .minimized }
        if window.isFullScreen { return .fullscreen }
        return .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect { window?.extensionFrame ?? .null }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.extensionScreenFrame ?? .null }

    func focus(for context: WKWebExtensionContext) async throws {
        window?.focusWindow()
    }

    func close(for context: WKWebExtensionContext) async throws {
        window?.closeWindow()
    }
}

/// Sela's tabs, as WebKit's extension APIs see them.
@available(macOS 15.4, *)
extension WebKitTab: WKWebExtensionTab {
    private var hostWindow: (any ExtensionWindow)? {
        engine.extensions?.window(containing: self)?.window
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        engine.extensions?.window(containing: self)
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        hostWindow?.extensionTabs.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }

    func title(for context: WKWebExtensionContext) -> String? { webView.title }

    func url(for context: WKWebExtensionContext) -> URL? { webView.url }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }

    func isPinned(for context: WKWebExtensionContext) -> Bool { hostWindow?.isPinned(self) ?? false }

    func isSelected(for context: WKWebExtensionContext) -> Bool { hostWindow?.activeExtensionTab === self }

    func size(for context: WKWebExtensionContext) -> CGSize { webView.bounds.size }

    func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { load(url) }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
    }

    func goBack(for context: WKWebExtensionContext) async throws { webView.goBack() }

    func goForward(for context: WKWebExtensionContext) async throws { webView.goForward() }

    func activate(for context: WKWebExtensionContext) async throws {
        guard let hostWindow else { throw ExtensionRequestFailed(message: "The tab isn't in a window.") }
        hostWindow.activate(self)
    }

    func close(for context: WKWebExtensionContext) async throws {
        if let hostWindow {
            hostWindow.close(self)
        } else {
            delegate?.tabDidRequestClose(self)
        }
    }

    /// A click on the extension's button counts as allowing it on this page, like Safari's.
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }
}
