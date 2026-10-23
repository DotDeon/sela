import BrowserEngine
import Foundation

/// An engine with no web content, for tests and previews.
@MainActor
public final class FakeEngine: BrowserEngine {
    public private(set) var madeTabs: [FakeTab] = []

    public init() {}

    public func makeTab(url: URL?) -> any BrowserTab {
        makeFakeTab(url: url)
    }

    func makeFakeTab(url: URL?) -> FakeTab {
        let tab = FakeTab(engine: self)
        if let url { tab.load(url) }
        madeTabs.append(tab)
        return tab
    }
}
