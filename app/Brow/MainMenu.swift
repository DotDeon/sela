import AppKit

/// The menu bar, built in code. Items without a target go to the first responder.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(viewMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Brow")
        menu.addItem(item("About Brow", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Brow", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Brow", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Tab", #selector(BrowserWindowController.newTab(_:)), "t"))
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(item("Open Location…", #selector(BrowserWindowController.focusAddressBar(_:)), "l"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(BrowserWindowController.closeTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Reload Page", #selector(BrowserWindowController.reloadTab(_:)), "r"))
        menu.addItem(item("Stop", #selector(BrowserWindowController.stopTab(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item("Back", #selector(BrowserWindowController.goBackInTab(_:)), "["))
        menu.addItem(item("Forward", #selector(BrowserWindowController.goForwardInTab(_:)), "]"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Next Tab", #selector(BrowserWindowController.selectNextTab(_:)), "\t", [.control]))
        menu.addItem(item("Previous Tab", #selector(BrowserWindowController.selectPreviousTab(_:)), "\t", [.control, .shift]))
        for number in 1...9 {
            let title = number == 9 ? "Last Tab" : "Tab \(number)"
            let numbered = item(title, #selector(BrowserWindowController.selectTabByNumber(_:)), "\(number)")
            numbered.tag = number
            menu.addItem(numbered)
        }
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
