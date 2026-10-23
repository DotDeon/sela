import AppKit
import Foundation
import Testing
@testable import CommandBar

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
private final class Recorder {
    var actions: [CommandBarAction] = []
    var dismissals = 0
}

@MainActor
private func makePanel(query: String = "report") -> (CommandBarViewController, CommandBarModel, Recorder) {
    let model = CommandBarModel(mode: .newTab, sources: CommandBarSources(
        tabs: { [tab("Inbox – Gmail", "mail"), tab("Calendar", "cal")] },
        commands: [command("New Space")],
        archived: { _ in [archived("Old report")] },
        history: { _ in [history("Report history")] }
    ))
    model.query = query
    let recorder = Recorder()
    let controller = CommandBarViewController(
        model: model,
        icon: { _ in nil },
        onAction: { recorder.actions.append($0) },
        onDismiss: { recorder.dismissals += 1 }
    )
    controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
    controller.view.layoutSubtreeIfNeeded()
    return (controller, model, recorder)
}

@MainActor
private func send(_ selector: Selector, to controller: CommandBarViewController) -> Bool {
    controller.control(controller.searchField, textView: NSTextView(), doCommandBy: selector)
}

@MainActor @Test func showsOneRowPerResult() {
    let (controller, model, _) = makePanel()
    #expect(controller.tableView.numberOfRows == model.results.count)
    #expect(model.results.count == 3)
}

@MainActor @Test func downArrowMovesSelection() async throws {
    let (controller, model, _) = makePanel()
    #expect(send(#selector(NSResponder.moveDown(_:)), to: controller))
    #expect(model.selectedIndex == 1)
    try await eventually { controller.tableView.selectedRow == 1 }
}

@MainActor @Test func returnActivatesSelection() {
    let (controller, model, recorder) = makePanel()
    let expected = model.activate()
    #expect(send(#selector(NSResponder.insertNewline(_:)), to: controller))
    #expect(recorder.actions == [expected!])
}

@MainActor @Test func escapeDismisses() {
    let (controller, _, recorder) = makePanel()
    #expect(send(#selector(NSResponder.cancelOperation(_:)), to: controller))
    #expect(recorder.dismissals == 1)
    #expect(recorder.actions.isEmpty)
}

@MainActor @Test func typingUpdatesRows() async throws {
    let (controller, model, _) = makePanel()
    controller.searchField.stringValue = "inbox"
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
    #expect(model.query == "inbox")
    try await eventually { controller.tableView.numberOfRows == model.results.count && model.results.count == 2 }
}
