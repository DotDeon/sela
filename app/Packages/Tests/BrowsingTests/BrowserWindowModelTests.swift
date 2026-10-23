import Foundation
import Testing
import BrowserEngine
import Browsing
import FakeEngine

private func url(_ name: String) -> URL { URL(string: "https://\(name).example.com/")! }

/// Polls every 10 ms for up to 2 seconds.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

@MainActor
private struct Window {
    let engine = FakeEngine()
    let model: BrowserWindowModel

    init(_ names: String...) {
        model = BrowserWindowModel(engine: engine)
        for name in names { model.openTab(url: url(name)) }
    }

    func tab(_ name: String) -> FakeTab {
        model.tabs.compactMap { $0 as? FakeTab }.first { $0.state.url == url(name) }!
    }

    var order: [String] {
        model.tabs.map { $0.state.url?.host()?.components(separatedBy: ".").first ?? "?" }
    }

    var selected: String? {
        model.selectedTab?.state.url?.host()?.components(separatedBy: ".").first
    }
}

@MainActor @Test func openTabAppendsAndSelects() {
    let window = Window("a", "b")
    #expect(window.order == ["a", "b"])
    #expect(window.selected == "b")
}

@MainActor @Test func openTabInBackgroundKeepsSelection() {
    let window = Window("a")
    window.model.openTab(url: url("b"), select: false)
    #expect(window.order == ["a", "b"])
    #expect(window.selected == "a")
}

@MainActor @Test func closingSelectedSelectsTabBelow() {
    let window = Window("a", "b", "c")
    window.model.select(window.tab("b").id)
    window.model.close(window.tab("b").id)
    #expect(window.selected == "c")
}

@MainActor @Test func closingLastSelectsTabAbove() {
    let window = Window("a", "b", "c")
    window.model.close(window.tab("c").id)
    #expect(window.selected == "b")
}

@MainActor @Test func closingOnlyTabLeavesNoSelection() {
    let window = Window("a")
    window.model.close(window.tab("a").id)
    #expect(window.model.tabs.isEmpty)
    #expect(window.model.selectedTabID == nil)
}

@MainActor @Test func closeCallsTabClose() {
    let window = Window("a", "b")
    let a = window.tab("a")
    window.model.close(a.id)
    #expect(a.isClosed)
    #expect(window.order == ["b"])
}

@MainActor @Test func foregroundPopupOpensAfterOpenerAndIsSelected() {
    let window = Window("a", "b")
    window.tab("a").simulateOpen(url: url("p"), disposition: .foreground)
    #expect(window.order == ["a", "p", "b"])
    #expect(window.selected == "p")
}

@MainActor @Test func backgroundOpensKeepOrderAfterOpener() {
    let window = Window("a", "b")
    window.model.select(window.tab("a").id)
    window.tab("a").simulateOpen(url: url("c1"), disposition: .background)
    window.tab("a").simulateOpen(url: url("c2"), disposition: .background)
    #expect(window.order == ["a", "c1", "c2", "b"])
    #expect(window.selected == "a")
}

@MainActor @Test func closingPopupReturnsToOpener() {
    let window = Window("a", "b")
    window.tab("a").simulateOpen(url: url("p"), disposition: .foreground)
    window.model.close(window.tab("p").id)
    #expect(window.selected == "a")
}

@MainActor @Test func popupRequestingCloseIsClosed() {
    let window = Window("a")
    let popup = window.tab("a").simulateOpen(url: url("p"), disposition: .foreground)
    popup.simulateRequestClose()
    #expect(window.order == ["a"])
    #expect(popup.isClosed)
    #expect(window.selected == "a")
}

@MainActor @Test func selectNextAndPreviousWrap() {
    let window = Window("a", "b", "c")
    window.model.selectNext()
    #expect(window.selected == "a")
    window.model.selectPrevious()
    #expect(window.selected == "c")
    window.model.selectPrevious()
    #expect(window.selected == "b")
}

@MainActor @Test func selectNumberNineIsLast() {
    let window = Window("a", "b", "c", "d")
    window.model.select(number: 9)
    #expect(window.selected == "d")
    window.model.select(number: 2)
    #expect(window.selected == "b")
    window.model.select(number: 7)
    #expect(window.selected == "b")
}

@MainActor @Test func dialogOnSelectedTabWaitsForAnswer() async throws {
    let window = Window("a")
    let tab = window.tab("a")
    let answer = Task { await tab.simulateDialog(.confirm(message: "Leave?")) }
    try await eventually { window.model.dialogForSelectedTab?.dialog == .confirm(message: "Leave?") }
    let pending = try #require(window.model.dialogForSelectedTab)
    #expect(pending.tabID == tab.id)
    window.model.resolveDialog(pending.id, with: .accepted(text: nil))
    #expect(await answer.value == .accepted(text: nil))
    #expect(window.model.dialogForSelectedTab == nil)
}

@MainActor @Test func dialogInBackgroundTabWaitsUntilSelected() async throws {
    let window = Window("a", "b")
    let a = window.tab("a")
    let answer = Task { await a.simulateDialog(.alert(message: "Hi")) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(window.model.dialogForSelectedTab == nil)
    window.model.select(a.id)
    try await eventually { window.model.dialogForSelectedTab?.dialog == .alert(message: "Hi") }
    window.model.resolveDialog(window.model.dialogForSelectedTab!.id, with: .dismissed)
    #expect(await answer.value == .dismissed)
}

@MainActor @Test func closingTabDismissesItsDialog() async throws {
    let window = Window("a")
    let tab = window.tab("a")
    let answer = Task { await tab.simulateDialog(.prompt(message: "Name?", defaultText: nil)) }
    try await eventually { window.model.dialogForSelectedTab != nil }
    window.model.close(tab.id)
    #expect(await answer.value == .dismissed)
}

@MainActor @Test func commandClickedTabsCloseInReadingOrder() {
    let window = Window("a", "b")
    window.model.select(window.tab("a").id)
    for name in ["c1", "c2", "c3"] {
        window.tab("a").simulateOpen(url: url(name), disposition: .background)
    }
    window.model.select(window.tab("c1").id)
    window.model.close(window.tab("c1").id)
    #expect(window.selected == "c2")
    window.model.close(window.tab("c2").id)
    #expect(window.selected == "c3")
    window.model.close(window.tab("c3").id)
    #expect(window.selected == "a")
}

@MainActor @Test func openerIsForgottenAfterSelectingAnUnrelatedTab() {
    let window = Window("a", "b")
    window.tab("a").simulateOpen(url: url("p"), disposition: .foreground)
    window.model.select(window.tab("b").id)
    window.model.select(window.tab("p").id)
    window.model.close(window.tab("p").id)
    #expect(window.selected == "b")
}
