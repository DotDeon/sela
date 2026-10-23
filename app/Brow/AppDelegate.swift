import AppKit
import WebKitEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = WebKitEngine()
    private var windowControllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        newWindow(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    @objc func newWindow(_ sender: Any?) {
        let controller = BrowserWindowController(engine: engine)
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)
        controller.showWindow(nil)
        controller.newTab(nil)
    }
}
