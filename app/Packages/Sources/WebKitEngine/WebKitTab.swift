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

    @ObservationIgnored private let webView: WKWebView
    @ObservationIgnored private let engine: WebKitEngine
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var reloadedAfterCrash = false
    @ObservationIgnored private var faviconURL: URL?

    var contentView: NSView { webView }

    init(webView: WKWebView, engine: WebKitEngine) {
        self.webView = webView
        self.engine = engine
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        observeWebView()
    }

    func load(_ url: URL) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() { webView.goBack() }

    func goForward() { webView.goForward() }

    func reload() { webView.reload() }

    func stopLoading() { webView.stopLoading() }

    func close() {
        observations.forEach { $0.invalidate() }
        observations = []
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        // Unloads the page so its audio and video stop.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        state.isLoading = false
    }

    private func observeWebView() {
        let update: @Sendable (WKWebView) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.syncState() }
        }
        observations = [
            webView.observe(\.url) { webView, _ in update(webView) },
            webView.observe(\.title) { webView, _ in update(webView) },
            webView.observe(\.isLoading) { webView, _ in update(webView) },
            webView.observe(\.estimatedProgress) { webView, _ in update(webView) },
            webView.observe(\.canGoBack) { webView, _ in update(webView) },
            webView.observe(\.canGoForward) { webView, _ in update(webView) },
        ]
        syncState()
    }

    private func syncState() {
        if webView.url != state.url {
            // A new page: its icon is unknown until it finishes loading.
            faviconURL = nil
        }
        let next = TabState(
            url: webView.url,
            title: webView.title,
            isLoading: webView.isLoading,
            estimatedProgress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            faviconURL: faviconURL
        )
        guard next != state else { return }
        state = next
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
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              let disposition = newTabDisposition(modifiers: navigationAction.modifierFlags, buttonNumber: navigationAction.buttonNumber),
              let delegate
        else { return .allow }
        delegate.tab(self, didOpen: engine.makeTab(url: url), disposition: disposition)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        reloadedAfterCrash = false
        Task { await findFavicon() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let error = error as NSError
        guard !isIgnorable(error),
              let failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url
        else { return }
        webView.loadSimulatedRequest(URLRequest(url: failedURL), responseHTML: errorPageHTML(for: failedURL, error: error))
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
        let popup = WebKitTab(webView: WKWebView(frame: .zero, configuration: configuration), engine: engine)
        delegate.tab(self, didOpen: popup, disposition: .foreground)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.tabDidRequestClose(self)
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
