import AppKit
import BrowserEngine
import Observation
import WebKit

/// One `WKWebView`, mirrored into `TabState`.
@MainActor
@Observable
final class WebKitTab: NSObject, BrowserTab {
    let id = TabID.make()
    private(set) var state = TabState.blank
    @ObservationIgnored weak var delegate: (any BrowserTabDelegate)?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored let engine: WebKitEngine
    /// Matches the web view's data store, which WebKit fixes when the web view is made.
    @ObservationIgnored let profile: ProfileIdentifier
    /// True for an extension's own page, such as its options, which gets no content blocking.
    @ObservationIgnored let isExtensionPage: Bool
    @ObservationIgnored private(set) var isClosed = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var reloadedAfterCrash = false
    @ObservationIgnored private var faviconURL: URL?
    /// Whether the page now loading or showing gets content blocking.
    @ObservationIgnored private var isBlocking = true
    /// Whether the navigation now under way, and the page now shown, came from submitting a form.
    @ObservationIgnored private var loadingFromForm = false
    @ObservationIgnored private var showingFormResult = false
    /// The host whose early rules this tab's scripts now carry.
    @ObservationIgnored private var earlyRulesHost: String?
    /// True when the page now showing reads like an article.
    @ObservationIgnored private var isArticle = false
    /// The reader's own web view, laid over the page while reader mode is on.
    @ObservationIgnored private var readerView: WKWebView?
    @ObservationIgnored private let readerNavigation = ReaderNavigation()

    var contentView: NSView { webView }

    init(webView: WKWebView, engine: WebKitEngine, profile: ProfileIdentifier, isExtensionPage: Bool = false) {
        self.profile = profile
        self.webView = webView
        self.engine = engine
        self.isExtensionPage = isExtensionPage
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        readerNavigation.tab = self
        observeWebView()
    }

    func load(_ url: URL) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func snapshot() -> TabSnapshot {
        TabSnapshot(url: webView.url, title: webView.title, sessionState: webView.interactionState as? Data)
    }

    func find(_ text: String, backwards: Bool) async -> Bool {
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = true
        configuration.backwards = backwards
        return (try? await (readerView ?? webView).find(text, configuration: configuration))?.matchFound ?? false
    }

    func clearFind() {
        (readerView ?? webView).evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    // MARK: Reader

    /// Finds the article and lays a reader over the page, in a web view that runs no scripts.
    func showReader() async -> Bool {
        if readerView != nil { return true }
        guard !isClosed, !isExtensionPage, let pageURL = webView.url, let script = ReaderScripts.extract,
              let json = try? await webView.evaluateJavaScript(script, contentWorld: ReaderScripts.world) as? String,
              let article = try? JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8)),
              article.textLength >= ReaderArticle.minimumLength,
              // The page may have moved on while the script ran.
              !isClosed, webView.url == pageURL, readerView == nil
        else { return false }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = webView.configuration.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let reader = WKWebView(frame: webView.bounds, configuration: configuration)
        reader.autoresizingMask = [.width, .height]
        reader.allowsMagnification = true
        readerNavigation.pageURL = pageURL
        reader.navigationDelegate = readerNavigation
        reader.loadHTMLString(readerPageHTML(for: article), baseURL: pageURL)
        let pageHadFocus = hasFocus(webView)
        webView.addSubview(reader)
        readerView = reader
        if pageHadFocus { webView.window?.makeFirstResponder(reader) }
        syncState()
        return true
    }

    func hideReader() {
        guard readerView != nil else { return }
        removeReader()
        syncState()
    }

    /// Takes the reader away, giving keyboard focus back to the page when the reader had it.
    private func removeReader() {
        guard let reader = readerView else { return }
        let readerHadFocus = hasFocus(reader)
        reader.navigationDelegate = nil
        reader.removeFromSuperview()
        readerView = nil
        if readerHadFocus { webView.window?.makeFirstResponder(webView) }
    }

    /// A link clicked in the reader: a new tab for Cmd-clicks, otherwise the page itself, out of reader mode.
    func followReaderLink(to url: URL, modifiers: NSEvent.ModifierFlags, buttonNumber: Int) {
        guard let delegate else { return }
        if let disposition = newTabDisposition(modifiers: modifiers, buttonNumber: buttonNumber) {
            delegate.tab(self, didOpen: engine.makeTab(url: url, profile: profile), disposition: disposition)
            return
        }
        guard delegate.tab(self, shouldFollowLinkTo: url, shiftKey: modifiers.contains(.shift)) else { return }
        hideReader()
        load(url)
    }

    /// Measures the page that just loaded, and offers reader mode when it reads like an article.
    private func detectArticle() async {
        guard !isExtensionPage, let pageURL = webView.url, ["http", "https", "file"].contains(pageURL.scheme?.lowercased() ?? ""),
              let script = ReaderScripts.signals,
              let json = try? await webView.evaluateJavaScript(script, contentWorld: ReaderScripts.world) as? String,
              let signals = try? JSONDecoder().decode(ArticleSignals.self, from: Data(json.utf8)),
              webView.url == pageURL
        else { return }
        isArticle = signals.looksLikeArticle
        syncState()
    }

    private func hasFocus(_ view: NSView) -> Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder === view || responder.isDescendant(of: view)
    }

    // MARK: Picture in picture and thumbnails

    func enterPictureInPicture() async -> Bool {
        guard !isClosed else { return false }
        let result = try? await webView.callAsyncJavaScript(PictureInPictureScripts.enter, contentWorld: PictureInPictureScripts.world)
        return result as? Bool ?? false
    }

    func exitPictureInPicture() {
        guard !isClosed else { return }
        webView.callAsyncJavaScript(PictureInPictureScripts.exit, in: nil, in: PictureInPictureScripts.world, completionHandler: nil)
    }

    /// What's on screen in the tab, the reader when it shows. WebKit can only draw a page that has a size.
    func thumbnail(width: CGFloat) async -> NSImage? {
        let view = readerView ?? webView
        guard !isClosed, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        return try? await view.takeSnapshot(configuration: configuration)
    }

    // MARK: Printing

    func printOperation(with info: NSPrintInfo) -> NSPrintOperation? {
        guard !isClosed, webView.url != nil else { return nil }
        let operation = (readerView ?? webView).printOperation(with: info)
        // WebKit lays the page out to its print view's frame, which starts empty and would print nothing.
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        return operation
    }

    func pdf() async throws -> Data {
        try await (readerView ?? webView).pdf()
    }

    /// A page from a submitted form would be sent again on waking, and edited fields or a focused editor would be lost.
    func hasUnsavedState() async -> Bool {
        if showingFormResult { return true }
        let script = """
            (() => {
                for (const field of document.querySelectorAll('input, textarea, select')) {
                    if (field.type === 'hidden') continue;
                    if (field.type === 'checkbox' || field.type === 'radio') {
                        if (field.checked !== field.defaultChecked) return true;
                    } else if (field.tagName === 'SELECT') {
                        if ([...field.options].some(o => o.selected !== o.defaultSelected)) return true;
                    } else if (field.value !== field.defaultValue) {
                        return true;
                    }
                }
                return !!(document.activeElement && document.activeElement.isContentEditable);
            })()
            """
        return (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    func isPlayingMedia() async -> Bool {
        await webView.requestMediaPlaybackState() == .playing
    }

    /// Picks up from a snapshot: WebKit's own history and scroll position when there is one, otherwise the address.
    func restore(_ snapshot: TabSnapshot) {
        if let sessionState = snapshot.sessionState {
            webView.interactionState = sessionState
        } else if let url = snapshot.url {
            load(url)
        }
    }

    func goBack() { webView.goBack() }

    /// Puts the engine's current rules on this tab, or takes them off when the page has blocking turned off.
    func refreshContentBlocking() {
        guard !isExtensionPage else { return }
        engine.contentRules.apply(to: webView.configuration.userContentController, blocking: isBlocking)
    }

    /// Puts the rules for the page about to load into the page's start-up scripts.
    private func installPageScripts(for url: URL?) {
        guard !isExtensionPage else { return }
        earlyRulesHost = url?.host()
        let early = isBlocking ? url.flatMap { engine.pageScripts?($0, nil) } : nil
        PageScriptInjection.installScripts(on: webView.configuration.userContentController, early: early)
    }

    /// The page scripts for a page or frame in this tab, or nil when this tab's page has blocking off.
    func pageScripts(page: URL, top: URL?) -> PageScripts? {
        guard isBlocking else { return nil }
        return engine.pageScripts?(page, top)
    }

    private func setBlocking(_ blocking: Bool) {
        guard blocking != isBlocking else { return }
        isBlocking = blocking
        refreshContentBlocking()
    }

    func goForward() { webView.goForward() }

    func reload() { webView.reload() }

    func stopLoading() { webView.stopLoading() }

    func close() {
        isClosed = true
        removeReader()
        observations.forEach { $0.invalidate() }
        observations = []
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        // Unloads the page so its audio and video stop.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        state.isLoading = false
        engine.tabDidClose(self)
    }

    private func observeWebView() {
        let update: @Sendable (WKWebView) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.syncState() }
        }
        observations = [
            webView.observe(\.url) { webView, _ in update(webView) },
            webView.observe(\.title) { webView, _ in update(webView) },
            // Progress is read whenever something else changes, not watched: it ticks many times a second
            // while a page loads, and every tick would redraw the whole sidebar.
            webView.observe(\.isLoading) { webView, _ in update(webView) },
            webView.observe(\.canGoBack) { webView, _ in update(webView) },
            webView.observe(\.canGoForward) { webView, _ in update(webView) },
            webView.observe(\.cameraCaptureState) { webView, _ in update(webView) },
            webView.observe(\.microphoneCaptureState) { webView, _ in update(webView) },
        ]
        syncState()
    }

    private func syncState() {
        if webView.url != state.url {
            // A new page: its icon is unknown until it finishes loading.
            faviconURL = nil
            // Its article too, unless only the fragment changed, as when a page marks where you've scrolled to.
            let onlyFragmentChanged = state.url.flatMap { old in webView.url.map { isSameDocument(old, $0) } } ?? false
            if !onlyFragmentChanged {
                isArticle = false
                removeReader()
            }
        }
        let next = TabState(
            url: webView.url,
            title: webView.title,
            isLoading: webView.isLoading,
            estimatedProgress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            faviconURL: faviconURL,
            isUsingCameraOrMicrophone: webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none,
            isReaderAvailable: isArticle,
            isShowingReader: readerView != nil
        )
        guard next != state else { return }
        let previous = state
        state = next
        engine.tabStateDidChange(self, from: previous)
        delegate?.tabStateDidChange(self)
    }

    /// Reads the page's icon link, or falls back to `/favicon.ico` for web pages.
    private func findFavicon() async {
        let pageURL = webView.url
        let script = "(() => { const l = document.querySelector(\"link[rel~='icon'], link[rel='apple-touch-icon']\"); return l ? l.href : null })()"
        let href = try? await webView.evaluateJavaScript(script) as? String
        guard webView.url == pageURL else { return }
        faviconURL = href.flatMap(URL.init(string:)) ?? defaultFaviconURL(for: pageURL)
        syncState()
    }

    private func ask(_ dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard let delegate else { return .dismissed }
        return await delegate.tab(self, runDialog: dialog)
    }
}

extension WebKitTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        let policy = linkPolicy(for: navigationAction)
        // A new top-level page in this tab decides whether it blocks content, before anything on it loads.
        // Links that open elsewhere, or that the window takes for Peek, leave the page here as it is.
        if policy == .allow, navigationAction.targetFrame?.isMainFrame == true {
            setBlocking(engine.blocksContent(on: navigationAction.request.url))
            installPageScripts(for: navigationAction.request.url)
            loadingFromForm = navigationAction.request.httpMethod?.uppercased() == "POST"
        }
        return policy
    }

    /// Files the page can't show, or that the server sends as attachments, are downloaded.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let isAttachment = disposition.lowercased().hasPrefix("attachment")
        return navigationResponse.isForMainFrame && (isAttachment || !navigationResponse.canShowMIMEType) ? .download : .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        engine.track(WebKitDownload(download: download, tab: self))
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        engine.track(WebKitDownload(download: download, tab: self))
    }

    /// Committing settles the page's address after any redirects, so blocking follows the page actually shown.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        setBlocking(engine.blocksContent(on: webView.url))
        // A redirect landed somewhere else: carry that page's rules from here on, never the first site's.
        if webView.url?.host() != earlyRulesHost {
            installPageScripts(for: webView.url)
        }
        showingFormResult = loadingFromForm
    }

    /// Where a link goes: here, or somewhere else, in which case this tab cancels it.
    private func linkPolicy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, let delegate else { return .allow }
        if let disposition = newTabDisposition(modifiers: navigationAction.modifierFlags, buttonNumber: navigationAction.buttonNumber) {
            delegate.tab(self, didOpen: engine.makeTab(url: url, profile: profile), disposition: disposition)
            return .cancel
        }
        // A plain or Shift-click in the page itself. The window may send it to Peek instead.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let isWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        guard isMainFrame, isWeb else { return .allow }
        let shiftKey = navigationAction.modifierFlags.contains(.shift)
        return delegate.tab(self, shouldFollowLinkTo: url, shiftKey: shiftKey) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        reloadedAfterCrash = false
        Task { await findFavicon() }
        Task { await detectArticle() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let error = error as NSError
        guard !isIgnorable(error),
              let failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url
        else { return }
        webView.loadSimulatedRequest(URLRequest(url: failedURL), responseHTML: errorPageHTML(for: failedURL, error: error) { self.engine.searchURL?($0) })
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !reloadedAfterCrash else { return }
        reloadedAfterCrash = true
        webView.reload()
    }
}

/// `<scheme>://<host>/favicon.ico` for http and https pages. Nil for anything else.
private func defaultFaviconURL(for pageURL: URL?) -> URL? {
    guard let pageURL, let scheme = pageURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
          var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
    else { return nil }
    components.path = "/favicon.ico"
    components.query = nil
    components.fragment = nil
    return components.url
}

/// Cancelled loads, and loads WebKit handed elsewhere, aren't failures the user needs to see.
private func isIgnorable(_ error: NSError) -> Bool {
    (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
        || (error.domain == "WebKitErrorDomain" && [102, 204].contains(error.code))
}

extension WebKitTab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let delegate else { return nil }
        // A popup gets its own rules and page script, so blocking can differ between it and the page that opened it.
        let bridge = PageScriptBridge()
        configuration.userContentController = engine.makeContentController(bridge: bridge)
        // WebKit hands over the opener's configuration, so the popup shares its data store and profile.
        let popup = WebKitTab(webView: WKWebView(frame: .zero, configuration: configuration), engine: engine, profile: profile)
        bridge.tab = popup
        engine.register(popup)
        delegate.tab(self, didOpen: popup, disposition: .foreground)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.tabDidRequestClose(self)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        guard let delegate else { return nil }
        return await delegate.tab(self, chooseFiles: parameters.allowsMultipleSelection, allowsDirectories: parameters.allowsDirectories)
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        guard let delegate else { return .deny }
        let media: MediaCapture = switch type {
        case .camera: .camera
        case .microphone: .microphone
        default: .cameraAndMicrophone
        }
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        components.port = origin.port == 0 ? nil : origin.port
        guard let url = components.url else { return .deny }
        return await delegate.tab(self, mayCapture: media, forOrigin: url) ? .grant : .deny
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        _ = await ask(.alert(message: message))
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await ask(.confirm(message: message)) != .dismissed
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        if case .accepted(let text) = await ask(.prompt(message: prompt, defaultText: defaultText)) {
            return text
        }
        return nil
    }
}
