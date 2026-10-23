import Foundation
import Testing
import BrowserEngine
import FakeEngine

private let a = URL(string: "https://a.example.com/")!
private let b = URL(string: "https://b.example.com/")!
private let c = URL(string: "https://c.example.com/")!

@MainActor
private final class RecordingDelegate: BrowserTabDelegate {
    var opened: [(source: TabID, newTab: TabID, disposition: NewTabDisposition)] = []

    func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {
        opened.append((tab.id, newTab.id, disposition))
    }

    func tabDidRequestClose(_ tab: any BrowserTab) {}

    func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        .dismissed
    }
}

@MainActor
private func makeTab(_ url: URL? = nil) -> (FakeEngine, FakeTab) {
    let engine = FakeEngine()
    let tab = engine.makeTab(url: url) as! FakeTab
    return (engine, tab)
}

@MainActor @Test func loadStartsLoadingAndRecordsURL() {
    let (_, tab) = makeTab()
    tab.load(a)
    #expect(tab.state.url == a)
    #expect(tab.state.isLoading)
    #expect(tab.state.title == nil)
    #expect(tab.loadedURLs == [a])
}

@MainActor @Test func finishLoadingSetsTitle() {
    let (_, tab) = makeTab(a)
    tab.finishLoading(title: "A")
    #expect(!tab.state.isLoading)
    #expect(tab.state.title == "A")
    #expect(tab.state.estimatedProgress == 1)
}

@MainActor @Test func historyBackAndForward() {
    let (_, tab) = makeTab(a)
    tab.finishLoading(title: "A")
    tab.load(b)
    tab.finishLoading(title: "B")
    #expect(tab.state.canGoBack)
    #expect(!tab.state.canGoForward)

    tab.goBack()
    #expect(tab.state.url == a)
    #expect(tab.state.canGoForward)
    tab.goForward()
    #expect(tab.state.url == b)

    tab.goBack()
    tab.load(c)
    #expect(!tab.state.canGoForward)
    #expect(tab.state.canGoBack)
}

@MainActor @Test func simulateOpenReachesDelegate() {
    let (engine, tab) = makeTab(a)
    let delegate = RecordingDelegate()
    tab.delegate = delegate
    let newTab = tab.simulateOpen(url: b, disposition: .background)
    #expect(delegate.opened.count == 1)
    #expect(delegate.opened.first?.source == tab.id)
    #expect(delegate.opened.first?.newTab == newTab.id)
    #expect(delegate.opened.first?.disposition == .background)
    #expect(newTab.state.url == b)
    #expect(engine.madeTabs.count == 2)
}

@MainActor @Test func simulateDialogWithoutDelegateIsDismissed() async {
    let (_, tab) = makeTab(a)
    #expect(await tab.simulateDialog(.alert(message: "hi")) == .dismissed)
}

@MainActor @Test func closeMarksClosed() {
    let (_, tab) = makeTab(a)
    tab.close()
    #expect(tab.isClosed)
}
