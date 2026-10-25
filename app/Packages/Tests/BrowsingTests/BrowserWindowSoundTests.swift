import FakeEngine
import Foundation
import Testing
import SelaTestSupport
import Browsing
import Sidebar
import SidebarModel

@MainActor
private func makeModel() throws -> BrowserWindowModel {
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    return BrowserWindowModel(engine: FakeEngine(), sidebar: store, zoomStore: PageZoomStore(defaults: UserDefaults(suiteName: "sela-sound-\(UUID().uuidString)")!))
}

@MainActor @Test func muteTabTogglesTheSelectedPage() throws {
    let model = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1"))
    model.toggleMute()
    #expect(tab.state.isMuted)
    model.toggleMute()
    #expect(!tab.state.isMuted)
}

@MainActor @Test func mutingFromTheSidebarOnlyReachesLivePages() throws {
    let model = try makeModel()
    model.select("u1")
    model.toggleMute("p1")
    #expect(model.liveTab(for: "p1") == nil)
    model.toggleMute("u1")
    #expect(model.liveTab(for: "u1")?.state.isMuted == true)
}

/// Muting lives with the page. A closed tab comes back with sound.
@MainActor @Test func muteIsNotKept() throws {
    let model = try makeModel()
    model.select("p1")
    model.toggleMute()
    model.close("p1")
    model.select("p1")
    #expect(model.liveTab(for: "p1")?.state.isMuted == false)
}

@MainActor @Test func littleSelaMutesItsPage() {
    let little = LittleWindowModel(engine: FakeEngine(), url: URL(string: "https://example.org/")!)
    little.toggleMute()
    #expect(little.tab?.state.isMuted == true)
}
