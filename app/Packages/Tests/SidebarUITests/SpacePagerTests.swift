import AppKit
import Foundation
import Testing
import SelaTestSupport
import BrowserEngine
import Browsing
import FakeEngine
import Favicons
import Sidebar
import SidebarModel
@testable import SidebarUI

private struct Offline: Error {}

@MainActor
private struct Harness {
    let model: BrowserWindowModel
    let controller: SidebarViewController
    let window: NSWindow

    init(prepare: (SidebarStore) -> Void = { _ in }) throws {
        let folder = try temporaryFolder()
        let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
        prepare(store)
        model = BrowserWindowModel(engine: FakeEngine(), sidebar: store)
        let favicons = FaviconStore(cacheFolder: folder, fetch: { _ in throw Offline() })
        controller = SidebarViewController(model: model, favicons: favicons)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()
    }

    /// Sends a trackpad swipe to the first page's list, as the system would.
    /// Each step is a sideways move in points and when it happens, in seconds.
    func swipe(_ steps: [(dx: Int32, at: TimeInterval)], endingAt end: TimeInterval, phase: Int64 = 4) throws {
        let list = try #require(controller.pager.pages[0].outlineView.enclosingScrollView)
        for (index, step) in steps.enumerated() {
            list.scrollWheel(with: scrollEvent(phase: index == 0 ? 1 : 2, dx: step.dx, at: step.at))
        }
        list.scrollWheel(with: scrollEvent(phase: phase, dx: 0, at: end))
    }
}

/// A trackpad scroll event. Phases: 1 began, 2 changed, 4 ended, 8 cancelled. A negative `dx` moves towards later spaces.
private func scrollEvent(phase: Int64, dx: Int32, at time: TimeInterval) -> NSEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0)!
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.timestamp = CGEventTimestamp(time * 1_000_000_000)
    return NSEvent(cgEvent: event)!
}

@MainActor @Test func aFlickMovesToTheNextSpace() throws {
    let h = try Harness()
    try h.swipe([(-20, 1.0), (-60, 1.02), (-60, 1.04)], endingAt: 1.06)
    #expect(h.model.selectedSpaceID == "S2")
    #expect(h.controller.pager.currentPage == 1)
}

@MainActor @Test func aSwipeThatStopsBeforeLiftingSettlesOnTheNearestPage() throws {
    let h = try Harness()
    // Quick at first, then the fingers rest a second before lifting, under half a page along.
    try h.swipe([(-10, 1.0), (-30, 1.02), (-30, 1.04)], endingAt: 2.0)
    #expect(h.model.selectedSpaceID == "S")
    #expect(h.controller.pager.currentPage == 0)
}

@MainActor @Test func aCancelledSwipeGoesBackToItsSpace() throws {
    let h = try Harness()
    try h.swipe([(-20, 1.0), (-60, 1.02), (-60, 1.04)], endingAt: 1.06, phase: 8)
    #expect(h.model.selectedSpaceID == "S")
    #expect(h.controller.pager.currentPage == 0)
}

@MainActor @Test func aWindowOpeningOnTheSecondSpaceShowsItsPage() throws {
    let h = try Harness { store in store.markActive("q1", at: fixtureDate.addingTimeInterval(1000)) }
    #expect(h.model.selectedSpaceID == "S2")
    #expect(h.controller.pager.currentPage == 1)
    let pager = h.controller.pager
    #expect(pager.contentView.bounds.origin.x == pager.contentView.bounds.width)
}

@MainActor @Test func aSwipeCutOffBySpacesChangingDoesntStickThePager() async throws {
    let h = try Harness()
    let list = try #require(h.controller.pager.pages[0].outlineView.enclosingScrollView)
    // The fingers are down and moving when another window adds a space. No end event follows.
    list.scrollWheel(with: scrollEvent(phase: 1, dx: -20, at: 1.0))
    list.scrollWheel(with: scrollEvent(phase: 2, dx: -20, at: 1.02))
    h.model.sidebar.addSpace(title: "Three")
    for _ in 0..<200 where h.controller.pager.pages.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(h.controller.pager.pages.count == 3)
    // A click on the space bar still moves the pager.
    h.model.selectSpace("S2")
    for _ in 0..<200 where h.controller.pager.currentPage != 1 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(h.controller.pager.currentPage == 1)
}
