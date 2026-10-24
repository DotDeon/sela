import BrowserEngine
import Foundation

/// An engine with no web content, for tests and previews.
@MainActor
public final class FakeEngine: ContentBlockingEngine {
    public private(set) var madeTabs: [FakeTab] = []
    /// What the last `installContentRules` call installed.
    public private(set) var installedRuleSets: [ContentRuleSet] = []
    public private(set) var installCount = 0
    /// Every snapshot a tab was restored from, oldest first.
    public private(set) var restoredSnapshots: [TabSnapshot] = []
    public var isContentBlockingEnabled: (@MainActor (URL) -> Bool)?
    public var pageScripts: (@MainActor (URL, URL?) -> PageScripts?)?
    /// What `supportsExtensions` answers.
    public var extensionsSupported = true
    /// When set, loading any extension fails with this message.
    public var extensionLoadFailure: String?
    public internal(set) var loadedExtensions: [String: FakeExtension] = [:]
    /// The extensions whose buttons were clicked, oldest first.
    public internal(set) var performedActions: [String] = []
    public internal(set) var activatedTabs: [TabID] = []
    public var extensionHost: (any ExtensionHost)?
    public var onExtensionPermissionsChanged: (@MainActor (String, ExtensionPermissions) -> Void)?

    public init() {}

    public func makeTab(url: URL?) -> any BrowserTab {
        makeFakeTab(url: url)
    }

    public func installContentRules(_ ruleSets: [ContentRuleSet]) async throws {
        installedRuleSets = ruleSets
        installCount += 1
    }

    public func makeTab(restoring snapshot: TabSnapshot) -> any BrowserTab {
        restoredSnapshots.append(snapshot)
        return makeFakeTab(url: snapshot.url)
    }

    func makeFakeTab(url: URL?) -> FakeTab {
        let tab = FakeTab(engine: self)
        if let url { tab.load(url) }
        madeTabs.append(tab)
        return tab
    }
}
