import CoreGraphics
import Foundation
import Testing
import Archive
import BrowserEngine
import Browsing
import FakeEngine
import SelaTestSupport
import Sidebar
import SidebarModel

private let page = URL(string: "https://news.example.com/story")!

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-little-\(UUID().uuidString)")!
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let archive: ArchiveStore
    let model: LittleWindowModel

    init(url: URL? = page, defaults: UserDefaults = freshDefaults()) throws {
        let folder = try temporaryFolder()
        archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { fixtureDate })
        model = LittleWindowModel(engine: engine, url: url, archive: archive, permissions: SitePermissions(defaults: defaults), now: { fixtureDate })
    }

    var tab: FakeTab? { model.tab as? FakeTab }
}

// MARK: Settings and routing

@Test func linksFromOtherAppsOpenInLittleSelaByDefault() {
    #expect(ExternalLinkSettings(defaults: freshDefaults()).destination == .littleWindow)
}

@Test func theLinkDestinationIsRemembered() {
    let defaults = freshDefaults()
    ExternalLinkSettings(defaults: defaults).destination = .newTab
    #expect(ExternalLinkSettings(defaults: defaults).destination == .newTab)
}

@Test func anUnknownLinkDestinationFallsBackToLittleSela() {
    let defaults = freshDefaults()
    defaults.set("sideways", forKey: ExternalLinkSettings.key)
    #expect(ExternalLinkSettings(defaults: defaults).destination == .littleWindow)
}

@Test func onlyWebPagesAndFilesAreOpened() {
    let file = URL(fileURLWithPath: "/tmp/page.html")
    let urls = [page, URL(string: "mailto:someone@example.com")!, file, URL(string: "HTTP://example.com")!]
    #expect(pagesToOpen(urls) == [page, file, URL(string: "HTTP://example.com")!])
}

@Test func launchingForALinkSkipsTheMainWindowOnlyForLittleSela() {
    #expect(!opensMainWindowAtLaunch(linksWaiting: [page], destination: .littleWindow))
    #expect(opensMainWindowAtLaunch(linksWaiting: [page], destination: .newTab))
    #expect(opensMainWindowAtLaunch(linksWaiting: [], destination: .littleWindow))
    #expect(opensMainWindowAtLaunch(linksWaiting: [URL(string: "mailto:a@example.com")!], destination: .littleWindow))
}

// MARK: Frames

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

@Test func theFirstWindowIsTheDefaultSizeInTheMiddle() {
    let frame = LittleWindowFrame(defaults: freshDefaults()).frameForNewWindow(visible: screen, occupied: [])
    #expect(frame == CGRect(x: 270, y: 87.5, width: 900, height: 700))
}

@Test func theSavedFrameIsUsedAgain() {
    let frames = LittleWindowFrame(defaults: freshDefaults())
    frames.saved = CGRect(x: 100, y: 50, width: 700, height: 500)
    #expect(frames.frameForNewWindow(visible: screen, occupied: []) == CGRect(x: 100, y: 50, width: 700, height: 500))
}

@Test func aSavedFrameOffScreenIsMovedBackOn() {
    let frames = LittleWindowFrame(defaults: freshDefaults())
    frames.saved = CGRect(x: 2000, y: -300, width: 3000, height: 500)
    #expect(frames.frameForNewWindow(visible: screen, occupied: []) == CGRect(x: 0, y: 0, width: 1440, height: 500))
}

@Test func aTinySavedFrameGrowsToTheMinimum() {
    let frames = LittleWindowFrame(defaults: freshDefaults())
    frames.saved = CGRect(x: 10, y: 10, width: 50, height: 50)
    #expect(frames.frameForNewWindow(visible: screen, occupied: []).size == LittleWindowFrame.minimumSize)
}

@Test func aSecondWindowStepsDownAndRight() {
    let frames = LittleWindowFrame(defaults: freshDefaults())
    let first = frames.frameForNewWindow(visible: screen, occupied: [])
    let second = frames.frameForNewWindow(visible: screen, occupied: [first])
    #expect(second == first.offsetBy(dx: 24, dy: -24))
    let third = frames.frameForNewWindow(visible: screen, occupied: [first, second])
    #expect(third == first.offsetBy(dx: 48, dy: -48))
}

@Test func steppingPastTheEdgeStartsAtTheTopLeft() {
    let frames = LittleWindowFrame(defaults: freshDefaults())
    frames.saved = CGRect(x: 540, y: 0, width: 900, height: 700)
    let next = frames.frameForNewWindow(visible: screen, occupied: [CGRect(x: 540, y: 0, width: 900, height: 700)])
    #expect(next == CGRect(x: 0, y: 175, width: 900, height: 700))
}

@Test func anUnreadableSavedFrameIsIgnored() {
    let defaults = freshDefaults()
    defaults.set([1.0, 2.0], forKey: LittleWindowFrame.key)
    #expect(LittleWindowFrame(defaults: defaults).saved == nil)
}

// MARK: The window's page

@MainActor @Test func opensItsLinkInANewPage() throws {
    let h = try Harness()
    #expect(h.tab?.loadedURLs == [page])
    #expect(h.model.selectedTab === h.model.tab)
}

@MainActor @Test func anEmptyWindowStartsBlankAndLoadsWhatIsTyped() throws {
    let h = try Harness(url: nil)
    #expect(h.tab?.loadedURLs == [])
    h.model.load(page)
    #expect(h.tab?.loadedURLs == [page])
}

@MainActor @Test func closingArchivesThePageLikeAClosedUnpinnedTab() throws {
    let h = try Harness()
    let tab = try #require(h.tab)
    tab.finishLoading(title: "A story")
    h.model.close()
    #expect(tab.isClosed)
    #expect(h.model.tab == nil)
    let entry = try #require(h.archive.entries.first)
    #expect(entry.url == page)
    #expect(entry.title == "A story")
    #expect(entry.reason == .closed)
    #expect(entry.archivedAt == fixtureDate)
}

@MainActor @Test func closingABlankWindowArchivesNothing() throws {
    let h = try Harness(url: nil)
    h.model.close()
    #expect(h.archive.entries.isEmpty)
}

@MainActor @Test func takingThePageKeepsItLiveAndOutOfTheArchive() throws {
    let h = try Harness()
    let tab = try #require(h.tab)
    let taken = h.model.takeTab()
    #expect(taken === tab)
    #expect(!tab.isClosed)
    #expect(tab.delegate == nil)
    h.model.close()
    #expect(h.archive.entries.isEmpty)
}

@MainActor @Test func visitsAreReportedOncePerAddress() throws {
    let h = try Harness()
    var visits: [URL] = []
    h.model.onPageVisited = { url, _ in visits.append(url) }
    h.tab?.finishLoading(title: "One")
    h.tab?.finishLoading(title: "One again")
    #expect(visits == [page])
}

@MainActor @Test func pagesItOpensGoToTheHandler() throws {
    let h = try Harness()
    var opened: [(any BrowserTab, NewTabDisposition)] = []
    h.model.onOpenTab = { opened.append(($0, $1)) }
    let popup = try #require(h.tab).simulateOpen(url: URL(string: "https://example.org/")!, disposition: .background)
    #expect(opened.count == 1)
    #expect(opened.first?.0 === popup)
    #expect(opened.first?.1 == .background)
    #expect(!popup.isClosed)
}

@MainActor @Test func pagesItOpensWithNoHandlerAreClosed() throws {
    let h = try Harness()
    let popup = try #require(h.tab).simulateOpen(url: URL(string: "https://example.org/")!, disposition: .foreground)
    #expect(popup.isClosed)
}

@MainActor @Test func windowCloseFromThePageAsksToClose() throws {
    let h = try Harness()
    var asked = false
    h.model.onCloseRequest = { asked = true }
    h.tab?.simulateRequestClose()
    #expect(asked)
}

@MainActor @Test func dialogsWaitForAnAnswer() async throws {
    let h = try Harness()
    let tab = try #require(h.tab)
    async let result = tab.simulateDialog(.confirm(message: "Leave?"))
    while h.model.dialogForSelectedTab == nil { await Task.yield() }
    let pending = try #require(h.model.dialogForSelectedTab)
    h.model.resolveDialog(pending.id, with: .accepted(text: nil))
    #expect(await result == .accepted(text: nil))
    #expect(h.model.dialogForSelectedTab == nil)
}

@MainActor @Test func closingDismissesAWaitingDialog() async throws {
    let h = try Harness()
    let tab = try #require(h.tab)
    async let result = tab.simulateDialog(.alert(message: "Hi"))
    while h.model.dialogForSelectedTab == nil { await Task.yield() }
    h.model.close()
    #expect(await result == .dismissed)
}

@MainActor @Test func cameraChoicesAreAskedOnceAndRemembered() async throws {
    let h = try Harness()
    var asked = 0
    h.model.onCaptureRequest = { _, _ in
        asked += 1
        return true
    }
    let tab = try #require(h.tab)
    let origin = URL(string: "https://meet.example.com")!
    #expect(await tab.simulateCaptureRequest(.camera, origin: origin))
    #expect(await tab.simulateCaptureRequest(.camera, origin: origin))
    #expect(asked == 1)
}

// MARK: Moving to a main window

@MainActor @Test func aMainWindowAdoptsTheLivePageWithoutReloading() throws {
    let h = try Harness()
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let window = BrowserWindowModel(engine: h.engine, sidebar: store, now: { fixtureDate })
    let tab = try #require(h.tab)
    let taken = try #require(h.model.takeTab())

    let id = window.adopt(taken)

    #expect(window.liveTab(for: id) === tab)
    #expect(window.selectedItemID == id)
    #expect(store.document.item("U")?.childIDs.first == id)
    #expect(tab.loadedURLs == [page])
    #expect(tab.delegate === window)
}

@MainActor @Test func adoptingInTheBackgroundKeepsTheSelection() throws {
    let h = try Harness()
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let window = BrowserWindowModel(engine: h.engine, sidebar: store, now: { fixtureDate })
    let before = window.selectedItemID
    let id = window.adopt(try #require(h.model.takeTab()), selecting: false)
    #expect(window.selectedItemID == before)
    #expect(store.document.item("U")?.childIDs.first == id)
}
