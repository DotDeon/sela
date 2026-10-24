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
