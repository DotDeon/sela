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
    var stateChanges = 0
    var followsLinks = true
    var askedLinks: [(URL, Bool)] = []

    func tab(_ tab: any BrowserTab, shouldFollowLinkTo url: URL, shiftKey: Bool) -> Bool {
        askedLinks.append((url, shiftKey))
        return followsLinks
    }

    func tabStateDidChange(_ tab: any BrowserTab) {
        stateChanges += 1
    }

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

@MainActor @Test func stateChangesReachDelegate() {
    let (_, tab) = makeTab()
    let delegate = RecordingDelegate()
    tab.delegate = delegate
    tab.load(a)
    tab.finishLoading(title: "A")
    #expect(delegate.stateChanges >= 2)
}

@MainActor @Test func finishLoadingSetsFavicon() {
    let (_, tab) = makeTab(a)
    tab.finishLoading(title: "A", faviconURL: URL(string: "https://a.example.com/icon.png"))
    #expect(tab.state.faviconURL == URL(string: "https://a.example.com/icon.png"))
}

@MainActor @Test func linkClickAsksTheDelegate() {
    let (_, tab) = makeTab(a)
    let delegate = RecordingDelegate()
    tab.delegate = delegate
    delegate.followsLinks = false
    tab.simulateLinkClick(to: b, shiftKey: true)
    #expect(tab.loadedURLs == [a])
    #expect(delegate.askedLinks.map(\.0) == [b])
    #expect(delegate.askedLinks.map(\.1) == [true])
    delegate.followsLinks = true
    tab.simulateLinkClick(to: c)
    #expect(tab.loadedURLs == [a, c])
}

@MainActor @Test func fakeRestoreLoadsTheSnapshotAddress() {
    let engine = FakeEngine()
    let snap = TabSnapshot(url: b, title: "B", sessionState: Data([1, 2]))
    let tab = engine.makeTab(restoring: snap) as! FakeTab
    #expect(tab.loadedURLs == [b])
    #expect(engine.restoredSnapshots == [snap])
}

@MainActor @Test func fakeMediaHooks() async {
    let (_, tab) = makeTab(a)
    let delegate = RecordingDelegate()
    tab.delegate = delegate
    #expect(await tab.isPlayingMedia() == false)
    tab.isPlayingMediaForTesting = true
    #expect(await tab.isPlayingMedia())
    let changes = delegate.stateChanges
    tab.setUsingCameraOrMicrophone(true)
    #expect(tab.state.isUsingCameraOrMicrophone)
    #expect(delegate.stateChanges == changes + 1)
}

@MainActor
private final class AnsweringDelegate: BrowserTabDelegate {
    func tabStateDidChange(_ tab: any BrowserTab) {}
    func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {}
    func tabDidRequestClose(_ tab: any BrowserTab) {}
    func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult { .dismissed }
    func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? { allowsMultiple ? [a, b] : [a] }
    func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool { media == .camera }
}

@MainActor @Test func fakeRequestsReachTheDelegate() async {
    let (_, tab) = makeTab(a)
    let delegate = AnsweringDelegate()
    tab.delegate = delegate
    #expect(await tab.simulateChooseFiles(multiple: true, directories: false) == [a, b])
    #expect(await tab.simulateCaptureRequest(.camera, origin: a))
    #expect(await tab.simulateCaptureRequest(.microphone, origin: a) == false)
}

@MainActor @Test func fakeRequestsDefaultToNo() async {
    let (_, tab) = makeTab(a)
    let delegate = RecordingDelegate()
    tab.delegate = delegate
    #expect(await tab.simulateChooseFiles(multiple: false, directories: false) == nil)
    #expect(await tab.simulateCaptureRequest(.cameraAndMicrophone, origin: a) == false)
}
