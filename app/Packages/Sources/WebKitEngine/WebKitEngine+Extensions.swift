import AppKit
import BrowserEngine
import WebKit

struct ExtensionsUnsupported: LocalizedError {
    var errorDescription: String? { "Extensions need macOS 15.4 or later." }
}

extension WebKitEngine: ExtensionEngine {
    public var supportsExtensions: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    public func readExtension(at folder: URL) async throws -> ExtensionDetails {
        guard #available(macOS 15.4, *), let extensions else { throw ExtensionsUnsupported() }
        return try await extensions.read(at: folder)
    }

    public func loadExtension(id: String, at folder: URL, permissions: ExtensionPermissions) async throws -> any BrowserExtension {
        guard #available(macOS 15.4, *), let extensions else { throw ExtensionsUnsupported() }
        return try await extensions.load(id: id, at: folder, permissions: permissions)
    }

    public func unloadExtension(id: String) {
        guard #available(macOS 15.4, *) else { return }
        extensions?.unload(id: id)
    }

    public func performAction(of browserExtension: any BrowserExtension, in tab: (any BrowserTab)?, anchor: NSView) {
        guard #available(macOS 15.4, *) else { return }
        extensions?.performAction(of: browserExtension.id, in: tab as? WebKitTab, anchor: anchor)
    }

    public func windowDidOpen(_ window: any ExtensionWindow) {
        guard #available(macOS 15.4, *) else { return }
        extensions?.windowDidOpen(window)
    }

    public func windowDidClose(_ window: any ExtensionWindow) {
        guard #available(macOS 15.4, *) else { return }
        extensions?.windowDidClose(window)
    }

    public func windowDidFocus(_ window: (any ExtensionWindow)?) {
        guard #available(macOS 15.4, *) else { return }
        extensions?.windowDidFocus(window)
    }

    public func tabDidActivate(_ tab: any BrowserTab, previous: (any BrowserTab)?) {
        guard #available(macOS 15.4, *), let tab = tab as? WebKitTab else { return }
        extensions?.tabDidActivate(tab, previous: previous as? WebKitTab)
    }
}
