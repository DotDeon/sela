import BrowserEngine
import CryptoKit
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
    /// The default profile's store, which extensions' background pages use too.
    private let dataStore: WKWebsiteDataStore
    /// Every other profile's store, made the first time a tab uses the profile.
    private var profileDataStores: [ProfileIdentifier: WKWebsiteDataStore] = [:]
    private let applicationName: String
    /// One set of page preferences for every web view, so a change reaches pages already open.
    let preferences = WKPreferences()
    let contentRules: WebKitContentRules
    /// Every tab still open, so new rules reach pages that are already showing.
    private let tabs = NSHashTable<WebKitTab>.weakObjects()

    /// Downloads still running, kept alive until they end.
    private var activeDownloads: [UUID: WebKitDownload] = [:]

    public var isContentBlockingEnabled: (@MainActor (URL) -> Bool)?
    public var pageScripts: (@MainActor (URL, URL?) -> PageScripts?)?
    /// A search for what was typed, linked from the page shown when a load fails. No link when nil.
    public var searchURL: (@MainActor (String) -> URL?)?
    public weak var extensionHost: (any ExtensionHost)?
    public var onExtensionPermissionsChanged: (@MainActor (String, ExtensionPermissions) -> Void)?
    /// The `WebKitExtensions` every web view shares, on systems that have it.
    private var extensionsStorage: AnyObject?

    /// Turns on Web Inspector for every page, open or new. `isInspectable` lets Safari's Develop menu in, and
    /// WebKit's developer extras put Inspect Element in the context menu and let the inspector open from here.
    /// Those extras are only reachable through a preference key WebKit doesn't publish, so that part is guarded.
    public var isInspectable = false {
        didSet {
            guard isInspectable != oldValue else { return }
            if preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) {
                preferences.setValue(isInspectable, forKey: "developerExtrasEnabled")
            }
            for tab in tabs.allObjects { tab.webView.isInspectable = isInspectable }
        }
    }

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
        preferences.isElementFullscreenEnabled = true
        allowPictureInPicture(preferences)
        preferences.javaScriptCanOpenWindowsAutomatically = configuration.allowsPopupsWithoutUserGesture
        if #available(macOS 15.4, *) {
            extensionsStorage = WebKitExtensions(engine: self, persistent: configuration.storage == .persistent, dataStore: dataStore)
        }
    }

    @available(macOS 15.4, *)
    var extensions: WebKitExtensions? { extensionsStorage as? WebKitExtensions }

    public func makeTab(url: URL?, profile: ProfileIdentifier) -> any BrowserTab {
        // An extension's own pages run in the extension's configuration, without content blocking.
        if #available(macOS 15.4, *), let url, let configuration = extensions?.webViewConfiguration(for: url) {
            let tab = WebKitTab(webView: WKWebView(frame: .zero, configuration: configuration), engine: self, profile: profile, isExtensionPage: true)
            register(tab)
            tab.load(url)
            return tab
        }
        let bridge = PageScriptBridge()
        let webView = WKWebView(frame: .zero, configuration: makeWebViewConfiguration(bridge: bridge, profile: profile))
        let tab = WebKitTab(webView: webView, engine: self, profile: profile)
        bridge.tab = tab
        register(tab)
        if let url { tab.load(url) }
        return tab
    }

    public func makeTab(restoring snapshot: TabSnapshot, profile: ProfileIdentifier) -> any BrowserTab {
        if #available(macOS 15.4, *), let url = snapshot.url, extensions?.webViewConfiguration(for: url) != nil {
            return makeTab(url: url, profile: profile)
        }
        let tab = makeTab(url: nil, profile: profile) as! WebKitTab
        tab.restore(snapshot)
        return tab
    }

    /// The store for a profile's cookies, logins, site storage and cache. Default uses WebKit's own default store,
    /// so Sela keeps what it stored before it had profiles.
    func dataStore(for profile: ProfileIdentifier) -> WKWebsiteDataStore {
        guard profile != .default else { return dataStore }
        if let existing = profileDataStores[profile] { return existing }
        let made: WKWebsiteDataStore = switch configuration.storage {
        case .persistent: WKWebsiteDataStore(forIdentifier: Self.storeIdentifier(for: profile))
        case .ephemeral: .nonPersistent()
        }
        profileDataStores[profile] = made
        return made
    }

    /// Empties the profile's store, then deletes it from disk. WebKit refuses to delete a store a web view still
    /// holds, and closed tabs can take a moment to let go, so deleting is tried a few times.
    public func removeWebsiteData(of profile: ProfileIdentifier) async {
        guard profile != .default else { return }
        let store = profileDataStores.removeValue(forKey: profile)
            ?? (configuration.storage == .persistent ? WKWebsiteDataStore(forIdentifier: Self.storeIdentifier(for: profile)) : nil)
        await store?.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        guard configuration.storage == .persistent else { return }
        for attempt in 0..<5 {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: Self.storeIdentifier(for: profile))
                return
            } catch {
                guard attempt < 4 else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// WebKit names stores by UUID. Sela's profile IDs are UUIDs, and anything else maps to a UUID made from its text.
    nonisolated static func storeIdentifier(for profile: ProfileIdentifier) -> UUID {
        if let uuid = UUID(uuidString: profile.rawValue) { return uuid }
        var bytes = Array(Insecure.MD5.hash(data: Data(profile.rawValue.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: bytes) as UUID
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

    /// Every profile shares the content rules, the extension controller and download handling. Only the data store differs.
    func makeWebViewConfiguration(bridge: PageScriptBridge, profile: ProfileIdentifier) -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore(for: profile)
        webConfiguration.applicationNameForUserAgent = applicationName
        webConfiguration.preferences = preferences
        webConfiguration.userContentController = makeContentController(bridge: bridge)
        if #available(macOS 15.4, *) {
            webConfiguration.webExtensionController = extensions?.controller
        }
        return webConfiguration
    }
}
