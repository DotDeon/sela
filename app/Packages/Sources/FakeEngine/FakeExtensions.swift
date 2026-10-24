import AppKit
import BrowserEngine
import Foundation
import Observation

/// An extension `FakeEngine` loaded. It runs nothing; tests change its button and permissions directly.
@MainActor
@Observable
public final class FakeExtension: BrowserExtension {
    public let id: String
    public let folder: URL
    public var details: ExtensionDetails
    public var permissions: ExtensionPermissions
    public var optionsPageURL: URL?
    /// The button it shows in every tab, or nil for none.
    public var actionState: ExtensionActionState?

    init(id: String, folder: URL, details: ExtensionDetails, permissions: ExtensionPermissions) {
        self.id = id
        self.folder = folder
        self.details = details
        self.permissions = permissions
        actionState = ExtensionActionState(label: details.name, badgeText: "", icon: nil, isEnabled: true)
    }

    public func icon(size: CGFloat) -> NSImage? { nil }

    public func action(for tab: (any BrowserTab)?) -> ExtensionActionState? { actionState }
}

public struct FakeExtensionError: Error, Equatable {
    public var message: String
}

extension FakeEngine: ExtensionEngine {
    public var supportsExtensions: Bool { extensionsSupported }

    /// Reads `name`, `version`, `description`, `permissions` and `host_permissions` from the folder's `manifest.json`.
    /// Patterns under `permissions`, as in older manifests, count as sites.
    public func readExtension(at folder: URL) async throws -> ExtensionDetails {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = manifest["name"] as? String
        else { throw FakeExtensionError(message: "No readable manifest") }
        let listed = (manifest["permissions"] as? [String] ?? []) + (manifest["host_permissions"] as? [String] ?? [])
        let patterns = listed.filter { $0 == "<all_urls>" || $0.contains("://") }
        return ExtensionDetails(
            name: name,
            version: manifest["version"] as? String,
            summary: manifest["description"] as? String,
            requestedPermissions: Set(listed).subtracting(patterns),
            requestedMatchPatterns: Set(patterns)
        )
    }

    public func loadExtension(id: String, at folder: URL, permissions: ExtensionPermissions) async throws -> any BrowserExtension {
        if let failure = extensionLoadFailure { throw FakeExtensionError(message: failure) }
        let loaded = FakeExtension(id: id, folder: folder, details: try await readExtension(at: folder), permissions: permissions)
        loadedExtensions[id] = loaded
        return loaded
    }

    public func unloadExtension(id: String) {
        loadedExtensions[id] = nil
    }

    public func performAction(of browserExtension: any BrowserExtension, in tab: (any BrowserTab)?, anchor: NSView) {
        performedActions.append(browserExtension.id)
    }

    public func windowDidOpen(_ window: any ExtensionWindow) {}

    public func windowDidClose(_ window: any ExtensionWindow) {}

    public func windowDidFocus(_ window: (any ExtensionWindow)?) {}

    public func tabDidActivate(_ tab: any BrowserTab, previous: (any BrowserTab)?) {
        activatedTabs.append(tab.id)
    }

    /// Acts as if the extension's permissions changed, as when the user answers a prompt.
    public func changePermissions(of id: String, to permissions: ExtensionPermissions) {
        loadedExtensions[id]?.permissions = permissions
        onExtensionPermissionsChanged?(id, permissions)
    }
}
