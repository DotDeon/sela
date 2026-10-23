import AppKit
import BrowserEngine

/// Where a link click should open. Nil means in the same tab.
func newTabDisposition(modifiers: NSEvent.ModifierFlags, buttonNumber: Int) -> NewTabDisposition? {
    if modifiers.contains(.command) {
        return modifiers.contains(.shift) ? .foreground : .background
    }
    if buttonNumber == 2 {
        return .background
    }
    return nil
}
