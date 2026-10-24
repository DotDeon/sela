import AppKit
import BrowserEngine
import Extensions

/// Web Extensions for the whole app: the installed list, and what extensions ask of Sela's windows and the user.
@MainActor
final class ExtensionsController: ExtensionHost {
    let library: ExtensionLibrary
    private var engine: any ExtensionEngine
    private let windowControllers: () -> [BrowserWindowController]
    private let makeWindow: ([URL]) -> BrowserWindowController

    init(engine: any ExtensionEngine, folder: URL, windowControllers: @escaping () -> [BrowserWindowController],
         makeWindow: @escaping ([URL]) -> BrowserWindowController) {
        self.engine = engine
        self.windowControllers = windowControllers
        self.makeWindow = makeWindow
        library = ExtensionLibrary(engine: engine, store: ExtensionStore(folder: folder))
        self.engine.extensionHost = self
    }

    func start() {
        Task { await library.start() }
    }

    /// The user clicked an extension's button in a window.
    func performAction(of item: any BrowserExtension, in window: BrowserWindowController, anchor: NSView) {
        engine.performAction(of: item, in: window.model.selectedTab, anchor: anchor)
    }

    func tabDidActivate(_ tab: any BrowserTab, previous: (any BrowserTab)?) {
        engine.tabDidActivate(tab, previous: previous)
    }

    func windowDidOpen(_ window: BrowserWindowController) { engine.windowDidOpen(window) }

    func windowDidClose(_ window: BrowserWindowController) { engine.windowDidClose(window) }

    func windowDidFocus(_ window: BrowserWindowController) { engine.windowDidFocus(window) }

    // MARK: Settings

    /// Asks for a folder or `.zip`, then installs it once the user agrees to what it asks for.
    func chooseAndInstall(window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an unpacked Web Extension folder or a .zip file with manifest.json inside."
        panel.prompt = "Add"
        Task {
            let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
            guard response == .OK, let source = panel.url else { return }
            do {
                try await library.install(from: source) { [weak self] details in
                    await self?.confirmInstall(details, window: window) ?? false
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Sela couldn't add this extension"
                alert.informativeText = error.localizedDescription
                await show(alert, in: window)
            }
        }
    }

    func confirmRemove(_ id: String, window: NSWindow?) {
        guard let entry = library.entries.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(entry.record.name)”?"
        alert.informativeText = "Sela deletes the extension's files and the data it saved."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        Task {
            if await show(alert, in: window) == .alertFirstButtonReturn { library.remove(id) }
        }
    }

    /// Opens an extension's settings page in a new tab in the front window.
    func openOptions(_ url: URL) {
        _ = openTab(url: url, in: nil, active: true, pinned: false)
    }

    private func confirmInstall(_ details: ExtensionDetails, window: NSWindow?) async -> Bool {
        let lines = PermissionSummary.lines(permissions: details.requestedPermissions, matchPatterns: details.requestedMatchPatterns)
        let alert = NSAlert()
        alert.messageText = "Add “\(details.name)”?"
        let access = lines.isEmpty ? "It doesn't ask for any special access." : "It will be able to:\n" + lines.map { "• \($0)" }.joined(separator: "\n")
        alert.informativeText = [details.version.map { "Version \($0)." }, access].compactMap { $0 }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return await show(alert, in: window) == .alertFirstButtonReturn
    }

    @discardableResult
    private func show(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.isVisible { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }

    // MARK: ExtensionHost

    /// Front to back, as the Window menu orders them.
    var extensionWindows: [any ExtensionWindow] {
        let controllers = windowControllers()
        let ordered = NSApp.orderedWindows.compactMap { window in controllers.first { $0.window === window } }
        return ordered + controllers.filter { controller in !ordered.contains { $0 === controller } }
    }

    var focusedExtensionWindow: (any ExtensionWindow)? { focusedController }

    private var focusedController: BrowserWindowController? {
        let controllers = windowControllers()
        return controllers.first { $0.window?.isMainWindow == true } ?? extensionWindows.first as? BrowserWindowController
    }

    func openTab(url: URL?, in window: (any ExtensionWindow)?, active: Bool, pinned: Bool) -> (any BrowserTab)? {
        let target = window as? BrowserWindowController ?? focusedController ?? makeWindow([])
        let id = target.model.newTab(url: url, selecting: active)
        if pinned { target.model.togglePin(id) }
        if active {
            target.showWindow(nil)
            NSApp.activate()
        }
        return target.model.liveTab(for: id)
    }

    func openWindow(urls: [URL], focused: Bool) -> (any ExtensionWindow)? {
        let controller = makeWindow(urls)
        if focused { NSApp.activate() }
        return controller
    }

    func askPermission(extensionName: String, permissions: Set<String>, matchPatterns: Set<String>) async -> Bool {
        let lines = PermissionSummary.lines(permissions: permissions, matchPatterns: matchPatterns)
        // Nothing the user needs a say in, such as storage or alarms.
        guard !lines.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "“\(extensionName)” wants more access"
        alert.informativeText = "It asks to:\n" + lines.map { "• \($0)" }.joined(separator: "\n") + "\n\nSela remembers your choice."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return await show(alert, in: focusedController?.window) == .alertFirstButtonReturn
    }

    func actionAnchor(forExtension id: String) -> NSView? {
        guard let controller = focusedController else { return nil }
        controller.revealSidebarForExtensions()
        return controller.sidebarController.extensionAnchor(for: id)
    }
}
