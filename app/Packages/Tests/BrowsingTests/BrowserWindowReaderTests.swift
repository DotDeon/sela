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
    return BrowserWindowModel(engine: FakeEngine(), sidebar: store)
}

@MainActor @Test func readerTogglesOnAndOffForArticles() async throws {
    let model = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    tab.simulateArticle(true)
    #expect(await model.toggleReader())
    #expect(tab.state.isShowingReader)
    #expect(await model.toggleReader())
    #expect(!tab.state.isShowingReader)
}

@MainActor @Test func readerRefusesPagesThatArentArticles() async throws {
    let model = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    #expect(await model.toggleReader() == false)
    #expect(!tab.state.isShowingReader)
}

@MainActor @Test func loadingAPageLeavesReaderMode() async throws {
    let model = try makeModel()
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    tab.simulateArticle(true)
    await model.toggleReader()
    model.load(URL(string: "https://elsewhere.example.com/")!)
    #expect(!tab.state.isShowingReader)
    #expect(!tab.state.isReaderAvailable)
}
