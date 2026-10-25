import BrowserEngine
import Foundation

/// An engine with no web content, for tests and previews.
@MainActor
public final class FakeEngine: ContentBlockingEngine {
    public private(set) var madeTabs: [FakeTab] = []
    public var isInspectable = false
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

    /// Profiles whose website data was removed, oldest first.
    public private(set) var removedProfiles: [ProfileIdentifier] = []

    public init() {}

    public func makeTab(url: URL?, profile: ProfileIdentifier) -> any BrowserTab {
        makeFakeTab(url: url, profile: profile)
    }

    public func installContentRules(_ ruleSets: [ContentRuleSet]) async throws {
        installedRuleSets = ruleSets
        installCount += 1
    }

    public func makeTab(restoring snapshot: TabSnapshot, profile: ProfileIdentifier) -> any BrowserTab {
        restoredSnapshots.append(snapshot)
        return makeFakeTab(url: snapshot.url, profile: profile)
    }

    public func removeWebsiteData(of profile: ProfileIdentifier) async {
        guard profile != .default else { return }
        removedProfiles.append(profile)
    }

    func makeFakeTab(url: URL?, profile: ProfileIdentifier) -> FakeTab {
        let tab = FakeTab(engine: self, profile: profile)
        if let url { tab.load(url) }
        madeTabs.append(tab)
        return tab
    }
}
