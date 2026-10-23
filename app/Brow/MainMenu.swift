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
        menu.addItem(submenu(tabMenu()))
        menu.addItem(submenu(spacesMenu()))
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
        menu.addItem(item("Toggle Sidebar", #selector(BrowserWindowController.toggleSidebar(_:)), "s"))
        menu.addItem(.separator())
        menu.addItem(item("Reload Page", #selector(BrowserWindowController.reloadTab(_:)), "r"))
        menu.addItem(item("Stop", #selector(BrowserWindowController.stopTab(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item("Back", #selector(BrowserWindowController.goBackInTab(_:)), "["))
        menu.addItem(item("Forward", #selector(BrowserWindowController.goForwardInTab(_:)), "]"))
        return menu
    }

    private static func tabMenu() -> NSMenu {
        let menu = NSMenu(title: "Tab")
        menu.addItem(item("Pin or Unpin Tab", #selector(BrowserWindowController.togglePin(_:)), "d"))
        menu.addItem(item("New Folder", #selector(BrowserWindowController.newFolder(_:)), "n", [.command, .option]))
        menu.addItem(item("Copy URL", #selector(BrowserWindowController.copyURL(_:)), "c", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Add Split View", #selector(BrowserWindowController.addSplitView(_:)), "=", [.control, .shift]))
        menu.addItem(item("Separate Split View", #selector(BrowserWindowController.separateSplitView(_:)), "-", [.control, .shift]))
        menu.addItem(item("Rotate Split View", #selector(BrowserWindowController.rotateSplitView(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Reopen Archived Tab", #selector(BrowserWindowController.reopenArchivedTab(_:)), "t", [.command, .shift]))
        let archiveAfter = NSMenuItem(title: "Archive Unpinned Tabs After", action: nil, keyEquivalent: "")
        let choices = NSMenu(title: "Archive Unpinned Tabs After")
        for hours in ArchiveSweeper.choices {
            let title = switch hours {
            case 0: "Never"
            case let h where h % 24 == 0 && h >= 48: "\(h / 24) Days"
            default: "\(hours) Hours"
            }
            let choice = item(title, #selector(AppDelegate.setArchiveInterval(_:)))
            choice.tag = hours
            choices.addItem(choice)
        }
        archiveAfter.submenu = choices
        menu.addItem(archiveAfter)
        return menu
    }

    private static func spacesMenu() -> NSMenu {
        let menu = NSMenu(title: "Spaces")
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        menu.addItem(item("Next Space", #selector(BrowserWindowController.selectNextSpace(_:)), right, [.command, .option]))
        menu.addItem(item("Previous Space", #selector(BrowserWindowController.selectPreviousSpace(_:)), left, [.command, .option]))
        menu.addItem(.separator())
        for number in 1...9 {
            let space = item("Space \(number)", #selector(BrowserWindowController.selectSpaceByNumber(_:)), "\(number)", [.control])
            space.tag = number
            menu.addItem(space)
        }
        menu.addItem(.separator())
        menu.addItem(item("New Space", #selector(BrowserWindowController.newSpace(_:))))
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
