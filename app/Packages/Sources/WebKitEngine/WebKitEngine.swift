import BrowserEngine
import Foundation
import WebKit

/// A browser engine built on `WKWebView`.
@MainActor
public final class WebKitEngine: ContentBlockingEngine {
    public struct Configuration: Sendable {
        public enum Storage: Sendable {
            /// Cookies and site data are kept between launches.
            case persistent
            /// Cookies and site data live only as long as this engine. For tests.
            case ephemeral
        }

        public var storage: Storage
        /// Lets pages call `window.open` without a click. For tests.
        public var allowsPopupsWithoutUserGesture: Bool

        public init(storage: Storage = .persistent, allowsPopupsWithoutUserGesture: Bool = false) {
            self.storage = storage
            self.allowsPopupsWithoutUserGesture = allowsPopupsWithoutUserGesture
        }
    }

    private let configuration: Configuration
    private let dataStore: WKWebsiteDataStore
    private let applicationName: String
    let contentRules: WebKitContentRules
    /// Every tab still open, so new rules reach pages that are already showing.
    private let tabs = NSHashTable<WebKitTab>.weakObjects()

    /// Downloads still running, kept alive until they end.
    private var activeDownloads: [UUID: WebKitDownload] = [:]

    public var isContentBlockingEnabled: (@MainActor (URL) -> Bool)?
    public var pageScripts: (@MainActor (URL, URL?) -> PageScripts?)?
    public weak var extensionHost: (any ExtensionHost)?
    public var onExtensionPermissionsChanged: (@MainActor (String, ExtensionPermissions) -> Void)?
    /// The `WebKitExtensions` every web view shares, on systems that have it.
    private var extensionsStorage: AnyObject?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        dataStore = switch configuration.storage {
        case .persistent: .default()
        case .ephemeral: .nonPersistent()
        }
        let ruleStore: WKContentRuleListStore = switch configuration.storage {
        case .persistent: .default()
        case .ephemeral: WKContentRuleListStore(url: FileManager.default.temporaryDirectory.appending(path: "sela-rules-\(UUID().uuidString)"))
        }
        contentRules = WebKitContentRules(store: ruleStore)
        applicationName = safariApplicationName(infoPlistURL: URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist"))
        if #available(macOS 15.4, *) {
            extensionsStorage = WebKitExtensions(engine: self, persistent: configuration.storage == .persistent, dataStore: dataStore)
        }
    }

    @available(macOS 15.4, *)
    var extensions: WebKitExtensions? { extensionsStorage as? WebKitExtensions }

    public func makeTab(url: URL?) -> any BrowserTab {
        // An extension's own pages run in the extension's configuration, without content blocking.
        if #available(macOS 15.4, *), let url, let configuration = extensions?.webViewConfiguration(for: url) {
            let tab = WebKitTab(webView: WKWebView(frame: .zero, configuration: configuration), engine: self, isExtensionPage: true)
            register(tab)
            tab.load(url)
            return tab
        }
        let bridge = PageScriptBridge()
        let tab = WebKitTab(webView: WKWebView(frame: .zero, configuration: makeWebViewConfiguration(bridge: bridge)), engine: self)
        bridge.tab = tab
        register(tab)
        if let url { tab.load(url) }
        return tab
    }

    public func makeTab(restoring snapshot: TabSnapshot) -> any BrowserTab {
        if #available(macOS 15.4, *), let url = snapshot.url, extensions?.webViewConfiguration(for: url) != nil {
            return makeTab(url: url)
        }
        let tab = makeTab(url: nil) as! WebKitTab
        tab.restore(snapshot)
        return tab
    }

    public func installContentRules(_ ruleSets: [ContentRuleSet]) async throws {
        try await contentRules.install(ruleSets)
        for tab in tabs.allObjects { tab.refreshContentBlocking() }
    }

    /// A tab's own content controller, with the current rules and the page script that asks `bridge` for more.
    func makeContentController(bridge: PageScriptBridge) -> WKUserContentController {
        let controller = WKUserContentController()
        contentRules.apply(to: controller, blocking: true)
        PageScriptInjection.install(on: controller, bridge: bridge)
        return controller
    }

    func track(_ download: WebKitDownload) {
        activeDownloads[download.id] = download
        download.onEnd = { [weak self] in self?.activeDownloads[$0.id] = nil }
    }

    /// Stops every download and removes its unfinished file. For quitting.
    public func discardActiveDownloads() {
        for download in activeDownloads.values { download.discard() }
        activeDownloads.removeAll()
    }

    /// Tracks a tab so rule changes reach it.
    func register(_ tab: WebKitTab) {
        tabs.add(tab)
        if #available(macOS 15.4, *) { extensions?.tabDidOpen(tab) }
    }

    func tabDidClose(_ tab: WebKitTab) {
        if #available(macOS 15.4, *) { extensions?.tabDidClose(tab) }
    }

    func tabStateDidChange(_ tab: WebKitTab, from previous: TabState) {
        if #available(macOS 15.4, *) { extensions?.tabStateDidChange(tab, from: previous) }
    }

    /// Whether pages at `url`, and the frames in them, get blocking.
    func blocksContent(on url: URL?) -> Bool {
        guard let url else { return true }
        return isContentBlockingEnabled?(url) ?? true
    }

    func makeWebViewConfiguration(bridge: PageScriptBridge) -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore
        webConfiguration.applicationNameForUserAgent = applicationName
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = configuration.allowsPopupsWithoutUserGesture
        webConfiguration.userContentController = makeContentController(bridge: bridge)
        if #available(macOS 15.4, *) {
            webConfiguration.webExtensionController = extensions?.controller
        }
        return webConfiguration
    }
}
