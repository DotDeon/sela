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

    public var isContentBlockingEnabled: (@MainActor (URL) -> Bool)?
    public var pageScripts: (@MainActor (URL, URL?) -> PageScripts?)?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        dataStore = switch configuration.storage {
        case .persistent: .default()
        case .ephemeral: .nonPersistent()
        }
        let ruleStore: WKContentRuleListStore = switch configuration.storage {
        case .persistent: .default()
        case .ephemeral: WKContentRuleListStore(url: FileManager.default.temporaryDirectory.appending(path: "brow-rules-\(UUID().uuidString)"))
        }
        contentRules = WebKitContentRules(store: ruleStore)
        applicationName = safariApplicationName(infoPlistURL: URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist"))
    }

    public func makeTab(url: URL?) -> any BrowserTab {
        let tab = WebKitTab(webView: WKWebView(frame: .zero, configuration: makeWebViewConfiguration()), engine: self)
        register(tab)
        if let url { tab.load(url) }
        return tab
    }

    public func installContentRules(_ ruleSets: [ContentRuleSet]) async throws {
        try await contentRules.install(ruleSets)
        for tab in tabs.allObjects { tab.refreshContentBlocking() }
    }

    /// Tracks a tab so rule changes reach it.
    func register(_ tab: WebKitTab) {
        tabs.add(tab)
    }

    /// Whether pages at `url`, and the frames in them, get blocking.
    func blocksContent(on url: URL?) -> Bool {
        guard let url else { return true }
        return isContentBlockingEnabled?(url) ?? true
    }

    func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore
        webConfiguration.applicationNameForUserAgent = applicationName
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = configuration.allowsPopupsWithoutUserGesture
        webConfiguration.userContentController = WKUserContentController()
        contentRules.apply(to: webConfiguration.userContentController, blocking: true)
        return webConfiguration
    }
}
