import AppKit
import BrowserEngine
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct TabSnapshotContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    @Test(arguments: EngineUnderTest.allCases)
    func snapshotsRestoreTheAddressAndHistory(engine: EngineUnderTest) async throws {
        let browser = engine.make()
        let a = try site.page("a.html", "<title>A</title>")
        let b = try site.page("b.html", "<title>B</title>")
        let tab = try await loadedTab(browser, a)
        tab.load(b)
        try await eventually { tab.state.title == "B" && tab.state.canGoBack }
        let snap = tab.snapshot()
        tab.close()

        let restored = browser.makeTab(restoring: snap)
        try await eventually { restored.state.title == "B" && restored.state.canGoBack }
        restored.goBack()
        try await eventually { restored.state.title == "A" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func snapshotsOfBlankTabsRestoreBlank(engine: EngineUnderTest) async throws {
        let browser = engine.make()
        let snap = browser.makeTab(url: nil).snapshot()
        let restored = browser.makeTab(restoring: snap)
        try await Task.sleep(for: .milliseconds(300))
        #expect(restored.state.url == nil)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func quietPagesAreNotPlayingMedia(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("a.html", "<title>A</title>"))
        #expect(await tab.isPlayingMedia() == false)
        #expect(tab.state.isUsingCameraOrMicrophone == false)
    }
}
