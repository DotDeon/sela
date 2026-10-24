import AppKit
import BrowserEngine
import Browsing
import SidebarUI

/// Shows the selected tab's JavaScript dialog as a sheet and sends back the answer.
@MainActor
final class DialogPresenter {
    private let model: BrowserWindowModel
    private weak var window: NSWindow?
    private var shown: (id: PendingDialog.ID, alert: NSAlert)?

    init(model: BrowserWindowModel, window: NSWindow) {
        self.model = model
        self.window = window
        keepObserving { [weak self] in self?.update() }
    }

    private func update() {
        let pending = model.dialogForSelectedTab
        guard pending?.id != shown?.id else { return }

        // The tab changed or its dialog went away. Take the sheet down without answering.
        if let shown, let sheet = window?.attachedSheet, sheet === shown.alert.window {
            window?.endSheet(sheet, returnCode: .abort)
        }
        shown = nil

        if let pending, let window {
            present(pending, in: window)
        }
    }

    private func present(_ pending: PendingDialog, in window: NSWindow) {
        let alert = NSAlert()
        var textField: NSTextField?
        switch pending.dialog {
        case .alert(let message):
            alert.messageText = message
            alert.addButton(withTitle: "OK")
        case .confirm(let message):
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
        case .prompt(let message, let defaultText):
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(string: defaultText ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            textField = field
        }
        if let host = model.selectedTab?.state.url?.host() {
            alert.informativeText = "From \(host)"
        }
        shown = (pending.id, alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response != .abort else { return }
            if self.shown?.id == pending.id { self.shown = nil }
            let result: JavaScriptDialogResult = response == .alertFirstButtonReturn
                ? .accepted(text: textField?.stringValue)
                : .dismissed
            self.model.resolveDialog(pending.id, with: result)
        }
        if let textField {
            alert.window.initialFirstResponder = textField
        }
    }
}
