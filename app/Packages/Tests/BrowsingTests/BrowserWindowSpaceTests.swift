import Foundation
import Testing
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Sidebar
import SidebarModel

private func url(_ name: String) -> URL { URL(string: "https://\(name).example.com/")! }

/// A clock that moves forward a second each time it's read.
@MainActor
private final class Clock {
    private var current = fixtureDate.addingTimeInterval(100)
    func now() -> Date {
        current = current.addingTimeInterval(1)
        return current
    }
}

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let clock = Clock()
    let store: SidebarStore
    let model: BrowserWindowModel

    init(prepare: (SidebarStore, Clock) -> Void = { _, _ in }) throws {
        let file = try temporaryFolder().appending(path: "Sidebar.json")
        let clock = clock
        store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: file), saveDelay: .seconds(60), now: clock.now, firstRunDocument: { fixtureDocument() })
        prepare(store, clock)
        model = BrowserWindowModel(engine: engine, sidebar: store, now: clock.now)
    }

    /// Another window on the same sidebar.
    func secondWindow() -> BrowserWindowModel {
        BrowserWindowModel(engine: engine, sidebar: store, now: clock.now)
    }

    func live(_ id: ItemID) -> FakeTab? {
        model.liveTab(for: id) as? FakeTab
    }
}

@MainActor @Test func launchShowsTheSpaceUsedLast() throws {
    let h = try Harness { store, clock in store.markActive("q1", at: clock.now()) }
    #expect(h.model.selectedSpaceID == "S2")
    #expect(h.model.selectedItemID == "q1")
}

@MainActor @Test func aNewWindowShowsTheSpaceUsedLast() throws {
    let h = try Harness()
    h.model.select("q1")
    let other = h.secondWindow()
    #expect(other.selectedSpaceID == "S2")
    #expect(other.selectedItemID == "q1")
}
