import BrowserEngine
import Foundation
import WebKit

/// A browser engine built on `WKWebView`.
@MainActor
public final class WebKitEngine: BrowserEngine {
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

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        dataStore = switch configuration.storage {
        case .persistent: .default()
        case .ephemeral: .nonPersistent()
        }
        applicationName = safariApplicationName(infoPlistURL: URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist"))
    }

    public func makeTab(url: URL?) -> any BrowserTab {
        let tab = WebKitTab(webView: WKWebView(frame: .zero, configuration: makeWebViewConfiguration()), engine: self)
        if let url { tab.load(url) }
        return tab
    }

    func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore
        webConfiguration.applicationNameForUserAgent = applicationName
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = configuration.allowsPopupsWithoutUserGesture
        return webConfiguration
    }
}
