import FakeEngine
import Foundation
import Testing
import SelaTestSupport
import Browsing
import Sidebar
import SidebarModel

@MainActor
private func makeModel() throws -> (BrowserWindowModel, UserDefaults) {
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let defaults = UserDefaults(suiteName: "sela-zoom-\(UUID().uuidString)")!
    return (BrowserWindowModel(engine: FakeEngine(), sidebar: store, zoomStore: PageZoomStore(defaults: defaults)), defaults)
}

@MainActor @Test func zoomingStepsTheSelectedPageAndRemembersItsSite() throws {
    let (model, defaults) = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1"))
    model.zoomIn()
    #expect(tab.state.pageZoom == 1.15)
    model.zoomIn()
    #expect(tab.state.pageZoom == 1.25)
    model.zoomOut()
    #expect(tab.state.pageZoom == 1.15)
    #expect(PageZoomStore(defaults: defaults).zoom(for: tab.state.url) == 1.15)
    model.resetZoom()
    #expect(tab.state.pageZoom == 1)
    #expect(defaults.object(forKey: PageZoomStore.key) == nil)
}

/// The fixture's tabs all live on example.com, so they share one level.
@MainActor @Test func zoomReachesEveryOpenPageOnTheSite() throws {
    let (model, _) = try makeModel()
    model.select("u1")
    model.select("u2")
    model.select("u1")
    model.zoomIn()
    #expect(model.liveTab(for: "u1")?.state.pageZoom == 1.15)
    #expect(model.liveTab(for: "u2")?.state.pageZoom == 1.15)
}

@MainActor @Test func newPagesOnTheSiteOpenAtItsLevel() throws {
    let (model, _) = try makeModel()
    model.select("u1")
    model.zoomIn()
    let id = model.newTab(url: URL(string: "https://fresh.example.com/")!)
    #expect(model.liveTab(for: id)?.state.pageZoom == 1.15)
    let elsewhere = model.newTab(url: URL(string: "https://elsewhere.test/")!)
    #expect(model.liveTab(for: elsewhere)?.state.pageZoom == 1)
}

@MainActor @Test func movingToAnotherSiteChangesTheLevel() throws {
    let (model, _) = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    model.zoomIn()
    tab.load(URL(string: "https://elsewhere.test/")!)
    #expect(tab.state.pageZoom == 1)
    tab.load(URL(string: "https://back.example.com/")!)
    #expect(tab.state.pageZoom == 1.15)
}

@MainActor @Test func zoomWithNothingSelectedDoesNothing() throws {
    let (model, defaults) = try makeModel()
    model.selectSpace("S2")
    model.close("q1")
    model.zoomIn()
    #expect(defaults.object(forKey: PageZoomStore.key) == nil)
}

@MainActor @Test func littleSelaFollowsTheSiteLevelToo() throws {
    let defaults = UserDefaults(suiteName: "sela-zoom-\(UUID().uuidString)")!
    let store = PageZoomStore(defaults: defaults)
    store.setZoom(1.5, for: URL(string: "https://example.org/")!)
    let little = LittleWindowModel(engine: FakeEngine(), url: URL(string: "https://example.org/a")!, zoomStore: store)
    #expect(little.tab?.state.pageZoom == 1.5)
    little.zoomOut()
    #expect(little.tab?.state.pageZoom == 1.25)
    #expect(store.zoom(for: URL(string: "https://example.org/")!) == 1.25)
}
