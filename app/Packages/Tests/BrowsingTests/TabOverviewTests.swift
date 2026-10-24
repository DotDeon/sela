import CoreGraphics
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

private func item(_ title: String, _ address: String) -> TabOverviewItem {
    TabOverviewItem(id: ItemID(rawValue: title), title: title, url: URL(string: address), isSelected: false, isLive: true)
}

@MainActor @Test func overviewShowsTheCurrentSpacesTabsInSidebarOrder() throws {
    let model = try makeModel()
    model.select("u1")
    let items = model.overviewItems
    // Folder "fold" holds p2, then p1, then today's tabs. Favourites and the other space stay out.
    #expect(items.map(\.id) == ["p2", "p1", "u1", "u2"])
    #expect(items.first { $0.id == "u1" }?.isSelected == true)
    #expect(items.first { $0.id == "u1" }?.isLive == true)
    #expect(items.first { $0.id == "p1" }?.isLive == false)
    #expect(items.first { $0.id == "p1" }?.title == "p1 title")
    model.selectSpace("S2")
    #expect(model.overviewItems.map(\.id) == ["q1"])
}

@Test func filteringMatchesEveryWordInTitleOrAddress() {
    let items = [item("Inbox", "https://mail.example.com/"), item("Swift forums", "https://www.swift.org/forums"), item("Recipes", "https://food.example.com/soup")]
    #expect(filterOverview(items, query: "").map(\.title) == ["Inbox", "Swift forums", "Recipes"])
    #expect(filterOverview(items, query: "swift").map(\.title) == ["Swift forums"])
    #expect(filterOverview(items, query: "SOUP food").map(\.title) == ["Recipes"])
    #expect(filterOverview(items, query: "swift soup").isEmpty)
    #expect(filterOverview(items, query: "https").isEmpty)
    #expect(filterOverview(items, query: "swift.org").map(\.title) == ["Swift forums"])
}

@Test func gridFitsAsManyColumnsAsTheWidthAllows() {
    let grid = OverviewGrid(width: 1064, count: 10)
    #expect(grid.columns == 4)
    #expect(grid.tileSize.width == 235)
    #expect(OverviewGrid(width: 300, count: 10).columns == 1)
    // Two tabs don't stretch across a wide window.
    let few = OverviewGrid(width: 2000, count: 2)
    #expect(few.columns == 2)
    #expect(few.tileSize.width == 330)
}

@Test func gridFramesCentreTheTilesAndCountDownFromTheTop() {
    let grid = OverviewGrid(width: 1064, count: 6)
    #expect(grid.frame(at: 0, width: 1064).origin == CGPoint(x: 32, y: 32))
    #expect(grid.frame(at: 5, width: 1064).origin == CGPoint(x: 32 + 255, y: 32 + grid.tileSize.height + 20))
    #expect(grid.contentSize(for: 6).height == 64 + grid.tileSize.height * 2 + 20)
    let few = OverviewGrid(width: 1200, count: 1)
    #expect(few.frame(at: 0, width: 1200).midX == 600)
}

@Test func arrowsMoveAroundTheGrid() {
    let grid = OverviewGrid(width: 1064, count: 6)
    #expect(grid.index(after: .right, from: 3, count: 6) == 4)
    #expect(grid.index(after: .left, from: 0, count: 6) == 0)
    #expect(grid.index(after: .right, from: 5, count: 6) == 5)
    #expect(grid.index(after: .down, from: 1, count: 6) == 5)
    #expect(grid.index(after: .down, from: 3, count: 6) == 5)
    #expect(grid.index(after: .down, from: 5, count: 6) == 5)
    #expect(grid.index(after: .up, from: 5, count: 6) == 1)
    #expect(grid.index(after: .up, from: 2, count: 6) == 2)
}
