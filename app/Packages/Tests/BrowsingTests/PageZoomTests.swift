import Foundation
import Testing
import Browsing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-zoom-\(UUID().uuidString)")!
}

@Test func stepsGoUpAndDownSafarisLadder() {
    #expect(PageZoom.zoomedIn(from: 1) == 1.15)
    #expect(PageZoom.zoomedIn(from: 1.15) == 1.25)
    #expect(PageZoom.zoomedOut(from: 1) == 0.85)
    #expect(PageZoom.zoomedOut(from: 0.85) == 0.75)
    #expect(PageZoom.steps.first == 0.5)
    #expect(PageZoom.steps.last == 3)
}

@Test func stepsStopAtTheEnds() {
    #expect(PageZoom.zoomedIn(from: 3) == 3)
    #expect(PageZoom.zoomedIn(from: 4) == 3)
    #expect(PageZoom.zoomedOut(from: 0.5) == 0.5)
    #expect(PageZoom.zoomedOut(from: 0.1) == 0.5)
}

/// A level between steps, such as one an extension set, moves to the nearest step in that direction.
@Test func stepsFromBetweenLevels() {
    #expect(PageZoom.zoomedIn(from: 1.1) == 1.15)
    #expect(PageZoom.zoomedOut(from: 1.1) == 1)
    #expect(PageZoom.zoomedIn(from: 1.1499999) == 1.25)
}

@Test func percentTextAndActualSize() {
    #expect(PageZoom.percentText(1.5) == "150%")
    #expect(PageZoom.percentText(0.85) == "85%")
    #expect(PageZoom.isActualSize(1))
    #expect(PageZoom.isActualSize(1.0000001))
    #expect(!PageZoom.isActualSize(1.15))
}

@Test func storeKeepsALevelPerSite() {
    let store = PageZoomStore(defaults: freshDefaults())
    let mail = URL(string: "https://mail.google.com/inbox")!
    let docs = URL(string: "https://docs.google.com/")!
    let other = URL(string: "https://example.org/")!
    #expect(store.zoom(for: mail) == 1)
    store.setZoom(1.5, for: mail)
    #expect(store.zoom(for: mail) == 1.5)
    #expect(store.zoom(for: docs) == 1.5, "subdomains share the site's level")
    #expect(store.zoom(for: other) == 1)
    #expect(PageZoomStore.sameSite(mail, docs))
    #expect(!PageZoomStore.sameSite(mail, other))
}

@Test func actualSizeForgetsTheSite() {
    let defaults = freshDefaults()
    let store = PageZoomStore(defaults: defaults)
    let url = URL(string: "https://example.org/")!
    store.setZoom(2, for: url)
    #expect(defaults.dictionary(forKey: PageZoomStore.key)?.count == 1)
    store.setZoom(1, for: url)
    #expect(store.zoom(for: url) == 1)
    #expect(defaults.object(forKey: PageZoomStore.key) == nil)
}

@Test func blankTabsAndOddSchemesHaveNoSite() {
    let defaults = freshDefaults()
    let store = PageZoomStore(defaults: defaults)
    store.setZoom(2, for: nil)
    store.setZoom(2, for: URL(string: "about:blank"))
    store.setZoom(2, for: URL(string: "webkit-extension://abc/options.html"))
    #expect(defaults.object(forKey: PageZoomStore.key) == nil)
    #expect(store.zoom(for: nil) == 1)
    #expect(!PageZoomStore.sameSite(nil, nil))
}

@Test func localFilesShareOneLevel() {
    let store = PageZoomStore(defaults: freshDefaults())
    store.setZoom(1.25, for: URL(fileURLWithPath: "/tmp/a.html"))
    #expect(store.zoom(for: URL(fileURLWithPath: "/Users/x/b.html")) == 1.25)
}

@Test func levelsSurviveAFreshStore() {
    let defaults = freshDefaults()
    PageZoomStore(defaults: defaults).setZoom(1.75, for: URL(string: "https://example.org/")!)
    #expect(PageZoomStore(defaults: defaults).zoom(for: URL(string: "https://www.example.org/page")!) == 1.75)
}
