import Foundation
import Testing
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

private func url(_ name: String) -> URL { URL(string: "https://\(name).example.com/")! }

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let store: SidebarStore
    let model: BrowserWindowModel
    /// A second profile, used by nothing until a test gives it to a space.
    let work: ProfileID

    init() throws {
        let file = try temporaryFolder().appending(path: "Sidebar.json")
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: file), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        model = BrowserWindowModel(engine: engine, sidebar: store)
        work = store.addProfile(name: "Work")
    }

    var workProfile: ProfileIdentifier { ProfileIdentifier(work) }

    func live(_ id: ItemID) -> FakeTab? {
        model.liveTab(for: id) as? FakeTab
    }
}

@MainActor @Test func tabsOpenInTheirSpacesProfile() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S2")
    #expect(h.live("u2")?.profile == .default)
    h.model.select("q1")
    #expect(h.live("q1")?.profile == h.workProfile)
    #expect(h.model.selectedProfile == h.workProfile)
}

@MainActor @Test func newTabsUseTheShownSpacesProfile() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S2")
    h.model.selectSpace("S2")
    let id = h.model.newTab(url: url("new"))
    #expect(h.live(id)?.profile == h.workProfile)
}

@MainActor @Test func aTabMovedToAnotherProfilesSpaceOpensAgainThereAtItsCurrentAddress() throws {
    let h = try Harness()
    h.model.select("u1")
    let old = try #require(h.live("u1"))
    old.load(url("elsewhere"))
    h.model.select("u2")
    h.store.setProfile(h.work, of: "S2")

    try h.store.move("u1", to: "U2", at: 0)
    h.model.reconcile()

    #expect(old.isClosed)
    #expect(h.live("u1") == nil)
    #expect(h.model.isSleeping("u1"))
    h.model.select("u1")
    let moved = try #require(h.live("u1"))
    #expect(moved.profile == h.workProfile)
    #expect(moved.loadedURLs == [url("elsewhere")])
    #expect(h.engine.restoredSnapshots.last?.sessionState == nil)
}

@MainActor @Test func changingTheShownSpacesProfileReloadsWhatsOnScreen() throws {
    let h = try Harness()
    let old = try #require(h.live("u2"))
    h.store.setProfile(h.work, of: "S")
    h.model.reconcile()
    #expect(old.isClosed)
    #expect(h.live("u2")?.profile == h.workProfile)
    #expect(h.live("u2")?.loadedURLs == [url("u2")])
}

@MainActor @Test func tabsThatKeepTheirProfileAreLeftAlone() throws {
    let h = try Harness()
    let old = try #require(h.live("u2"))
    try h.store.move("u2", to: "U2", at: 0)
    h.model.reconcile()
    h.model.select("u2")
    #expect(h.live("u2") === old)
    #expect(!old.isClosed)
}

@MainActor @Test func favouritesFollowTheShownSpacesProfile() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S2")
    h.model.select("f1")
    let homeFavourite = try #require(h.live("f1"))
    #expect(homeFavourite.profile == .default)

    h.model.selectSpace("S2")
    #expect(homeFavourite.isClosed)
    h.model.select("f1")
    #expect(h.live("f1")?.profile == h.workProfile)
}

@MainActor @Test func peekUsesTheProfileOfThePageThatOpenedIt() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S")
    h.model.reconcile()
    h.model.select("p1")
    h.live("p1")?.simulateLinkClick(to: URL(string: "https://elsewhere.org/")!)
    #expect(h.model.peekTab?.profile == h.workProfile)
}

@MainActor @Test func adoptingAPageFromAnotherProfileOpensItAgainInTheSpacesProfile() throws {
    let h = try Harness()
    let little = LittleWindowModel(engine: h.engine, url: url("story"), profile: h.workProfile)
    let taken = try #require(little.takeTab() as? FakeTab)

    let id = h.model.adopt(taken)

    #expect(taken.isClosed)
    let adopted = try #require(h.live(id))
    #expect(adopted !== taken)
    #expect(adopted.profile == .default)
    #expect(adopted.loadedURLs == [url("story")])
}

@MainActor @Test func adoptingAPageFromTheSameProfileKeepsIt() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S")
    h.model.reconcile()
    let little = LittleWindowModel(engine: h.engine, url: url("story"), profile: h.workProfile)
    let taken = try #require(little.takeTab() as? FakeTab)
    let id = h.model.adopt(taken)
    #expect(h.live(id) === taken)
    #expect(!taken.isClosed)
}

@MainActor @Test func deletingAProfileMovesItsTabsToDefault() throws {
    let h = try Harness()
    h.store.setProfile(h.work, of: "S")
    h.model.reconcile()
    #expect(h.live("u2")?.profile == h.workProfile)
    h.store.removeProfile(h.work)
    h.model.reconcile()
    #expect(h.live("u2")?.profile == .default)
    #expect(h.store.document.profiles.map(\.id) == [.default])
}

@MainActor @Test func aLittleWindowCanSwitchProfile() throws {
    let engine = FakeEngine()
    let work = ProfileIdentifier(rawValue: "work")
    let little = LittleWindowModel(engine: engine, url: url("story"), profile: work)
    let old = try #require(little.tab as? FakeTab)
    old.load(url("next"))
    little.switchProfile(to: .default)
    #expect(old.isClosed)
    #expect(little.tab?.profile == .default)
    #expect((little.tab as? FakeTab)?.loadedURLs == [url("next")])
}
