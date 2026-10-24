import Foundation
import Testing
import Archive
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

private let minute: TimeInterval = 60
private let other = URL(string: "https://elsewhere.example.org/page")!

@MainActor
private final class Clock {
    var now = fixtureDate.addingTimeInterval(100)
    func read() -> Date {
        now = now.addingTimeInterval(1)
        return now
    }
    func jump(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let clock = Clock()
    let store: SidebarStore
    let archive: ArchiveStore
    let model: BrowserWindowModel

    init() throws {
        let folder = try temporaryFolder()
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        let clock = clock
        archive = ArchiveStore(fileURL: folder.appending(path: "Archive.json"), now: { clock.now })
        model = BrowserWindowModel(engine: engine, sidebar: store, archive: archive, now: { clock.read() })
    }

    func live(_ id: ItemID) -> FakeTab? { model.liveTab(for: id) as? FakeTab }
}

@MainActor @Test func unusedTabsSleep() async throws {
    let h = try Harness()
    h.model.select("u1")
    let page = try #require(h.live("u1"))
    h.model.select("u2")
    h.clock.jump(20 * minute)
    let slept = await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(slept == ["u1"])
    #expect(h.live("u1") == nil)
    #expect(h.model.isSleeping("u1"))
    #expect(page.isClosed)
    #expect(h.live("u2") != nil)
}

@MainActor @Test func recentTabsStayAwake() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.select("u2")
    h.clock.jump(5 * minute)
    #expect(await h.model.sleepTabs(unusedFor: 15 * minute).isEmpty)
}

@MainActor @Test func wakingRestoresTheSnapshot() async throws {
    let h = try Harness()
    h.model.select("p1")
    h.live("p1")?.load(other)
    h.model.select("u1")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.model.isSleeping("p1"))
    h.model.select("p1")
    #expect(h.engine.restoredSnapshots.last?.url == other)
    #expect(h.live("p1")?.loadedURLs.first == other)
    #expect(!h.model.isSleeping("p1"))
}

@MainActor @Test func playingTabsNeverSleep() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.live("u1")?.isPlayingMediaForTesting = true
    h.model.select("u2")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.live("u1") != nil)
}

@MainActor @Test func callsNeverSleep() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.live("u1")?.setUsingCameraOrMicrophone(true)
    h.model.select("u2")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.live("u1") != nil)
}

@MainActor @Test func tabsWaitingOnADialogNeverSleep() async throws {
    let h = try Harness()
    h.model.select("u1")
    let page = try #require(h.live("u1"))
    let answer = Task { await page.simulateDialog(.alert(message: "x")) }
    try await Task.sleep(for: .milliseconds(50))
    h.model.select("u2")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.live("u1") != nil)
    h.model.select("u1")
    let dialog = try #require(h.model.dialogForSelectedTab)
    h.model.resolveDialog(dialog.id, with: .dismissed)
    _ = await answer.value
}

@MainActor @Test func memoryPressureKeepsWhatYouSee() async throws {
    let h = try Harness()
    h.model.select("p1")
    h.model.select("u1")
    h.model.openInSplit("u2")
    h.model.select("u1")
    h.live("u1")?.simulateLinkClick(to: other, shiftKey: true)
    let peek = try #require(h.model.peekTab as? FakeTab)
    let slept = await h.model.sleepTabs(unusedFor: 0)
    #expect(slept == ["p1"])
    #expect(h.live("u1") != nil)
    #expect(h.live("u2") != nil)
    #expect(h.model.peekTab != nil)
    #expect(!peek.isClosed)
}

@MainActor @Test func closingASleepingTabForgetsItsSnapshot() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.select("u2")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    h.model.close("u1")
    #expect(!h.model.isSleeping("u1"))
    #expect(h.archive.entries.first?.url == URL(string: "https://u1.example.com/"))
}

@MainActor @Test func wakingASplitWakesEveryPane() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.model.openInSplit("u2")
    h.model.select("p1")
    await h.model.sleepTabs(unusedFor: 0)
    #expect(h.model.isSleeping("u1") && h.model.isSleeping("u2"))
    h.model.select("u2")
    #expect(h.live("u1") != nil && h.live("u2") != nil)
    #expect(Set(h.engine.restoredSnapshots.compactMap(\.url)) == [URL(string: "https://u1.example.com/")!, URL(string: "https://u2.example.com/")!])
}

@MainActor @Test func pagesWithUnsavedWorkNeverSleep() async throws {
    let h = try Harness()
    h.model.select("u1")
    h.live("u1")?.hasUnsavedStateForTesting = true
    h.model.select("u2")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.live("u1") != nil)
}

@MainActor @Test func aSleepingPinnedTabStillShowsWhereItWas() async throws {
    let h = try Harness()
    h.model.select("p1")
    h.live("p1")?.load(other)
    h.live("p1")?.finishLoading(title: "Elsewhere")
    h.model.select("u1")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    #expect(h.model.isSleeping("p1"))
    #expect(h.model.currentPage(for: "p1")?.url == other)
    #expect(h.model.currentPage(for: "p1")?.title == "Elsewhere")
    #expect(h.model.isAwayFromSavedURL("p1"))
}

@MainActor @Test func resettingASleepingTabWakesItOnItsSavedAddress() async throws {
    let h = try Harness()
    h.model.select("p1")
    h.live("p1")?.load(other)
    h.model.select("u1")
    h.clock.jump(20 * minute)
    await h.model.sleepTabs(unusedFor: 15 * minute)
    h.model.resetToSavedURL("p1")
    #expect(h.live("p1")?.loadedURLs.first == URL(string: "https://p1.example.com/"))
    #expect(!h.model.isSleeping("p1"))
}
