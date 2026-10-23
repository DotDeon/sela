import Foundation
import Testing
@testable import CommandBar

@MainActor
private func makeModel(_ mode: CommandBarMode = .newTab) -> CommandBarModel {
    CommandBarModel(mode: mode, sources: CommandBarSources(
        tabs: { [tab("Inbox – Gmail", "mail"), tab("Calendar", "cal")] },
        commands: [command("New Space")],
        archived: { _ in [archived("Old report")] },
        history: { _ in [history("Report history")] }
    ))
}

@MainActor @Test func currentTabModeStartsWithAddress() {
    let model = makeModel(.currentTab(address: "https://mail.example.com/"))
    #expect(model.query == "https://mail.example.com/")
    #expect(model.results.first == .open(URL(string: "https://mail.example.com/")!, isSearch: false))
}

@MainActor @Test func typingResetsSelection() {
    let model = makeModel()
    model.query = "a"
    model.moveSelection(by: 2)
    model.query = "ab"
    #expect(model.selectedIndex == 0)
}

@MainActor @Test func selectionIsClamped() {
    let model = makeModel()
    model.query = "report"
    model.moveSelection(by: -1)
    #expect(model.selectedIndex == 0)
    model.moveSelection(by: 50)
    #expect(model.selectedIndex == model.results.count - 1)
}

@MainActor @Test func activateMapsResults() throws {
    let newTab = makeModel()
    newTab.query = "example.com"
    #expect(newTab.activate() == .open(URL(string: "https://example.com")!, inNewTab: true))

    let current = makeModel(.currentTab(address: ""))
    current.query = "example.com"
    #expect(current.activate() == .open(URL(string: "https://example.com")!, inNewTab: false))

    newTab.query = "inbox"
    #expect(newTab.activate() == .selectTab("tab-mail"))

    newTab.query = "new space"
    let commandIndex = try #require(newTab.results.firstIndex { if case .command = $0 { true } else { false } })
    #expect(newTab.activate(at: commandIndex) == .runCommand("new space"))

    newTab.query = "report"
    let archivedIndex = try #require(newTab.results.firstIndex { if case .archived = $0 { true } else { false } })
    guard case .restoreArchived = newTab.activate(at: archivedIndex) else {
        Issue.record("expected a restore")
        return
    }
    let historyIndex = try #require(newTab.results.firstIndex { if case .history = $0 { true } else { false } })
    #expect(newTab.activate(at: historyIndex) == .open(URL(string: "https://report-history.history.example.com/")!, inNewTab: true))
}

@MainActor @Test func activateWithNoResultsIsNil() {
    let model = CommandBarModel(mode: .newTab, sources: CommandBarSources(tabs: { [] }, commands: [], archived: { _ in [] }, history: { _ in [] }))
    #expect(model.activate() == nil)
}
