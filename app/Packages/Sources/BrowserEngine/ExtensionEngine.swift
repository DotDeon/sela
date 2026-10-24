import AppKit
import Observation

/// What an extension's folder says about it, read before it's turned on.
public struct ExtensionDetails: Equatable, Sendable {
    public var name: String
    public var version: String?
    public var summary: String?
    /// The manifest's permissions, such as `tabs` or `storage`.
    public var requestedPermissions: Set<String>
    /// The sites it asks for, as match patterns such as `*://*.example.com/*` or `<all_urls>`.
    public var requestedMatchPatterns: Set<String>

    public init(name: String, version: String?, summary: String? = nil, requestedPermissions: Set<String> = [], requestedMatchPatterns: Set<String> = []) {
        self.name = name
        self.version = version
        self.summary = summary
        self.requestedPermissions = requestedPermissions
        self.requestedMatchPatterns = requestedMatchPatterns
    }
}

/// Which permissions and sites the user allowed or refused an extension, and until when.
/// `Date.distantFuture` means for good.
public struct ExtensionPermissions: Codable, Equatable, Sendable {
    public var granted: [String: Date]
    public var denied: [String: Date]
    public var grantedMatchPatterns: [String: Date]
    public var deniedMatchPatterns: [String: Date]

    public init(granted: [String: Date] = [:], denied: [String: Date] = [:], grantedMatchPatterns: [String: Date] = [:], deniedMatchPatterns: [String: Date] = [:]) {
        self.granted = granted
        self.denied = denied
        self.grantedMatchPatterns = grantedMatchPatterns
        self.deniedMatchPatterns = deniedMatchPatterns
    }

    public static let none = ExtensionPermissions()
}

/// How an extension's toolbar button looks in one tab.
public struct ExtensionActionState: Equatable {
    public var label: String
    /// Short text the extension shows over its icon, such as a count. Empty for none.
    public var badgeText: String
    public var icon: NSImage?
    public var isEnabled: Bool

    public init(label: String, badgeText: String, icon: NSImage?, isEnabled: Bool) {
        self.label = label
        self.badgeText = badgeText
        self.icon = icon
        self.isEnabled = isEnabled
    }
}

/// An extension the engine has loaded. Implementations are `@Observable`, so reading `action(for:)`
/// inside observation tracking sees the extension change its button.
@MainActor
public protocol BrowserExtension: AnyObject, Observable {
    /// Sela's own name for this install, the same between launches.
    var id: String { get }
    var details: ExtensionDetails { get }
    /// What the user has allowed and refused so far.
    var permissions: ExtensionPermissions { get }
    /// The extension's settings page, when it has one.
    var optionsPageURL: URL? { get }
    func icon(size: CGFloat) -> NSImage?
    /// The toolbar button in `tab`, or nil when the extension has none.
    func action(for tab: (any BrowserTab)?) -> ExtensionActionState?
}

/// A browser window as extensions see it.
@MainActor
public protocol ExtensionWindow: AnyObject {
    /// The window's live tabs, in sidebar order.
    var extensionTabs: [any BrowserTab] { get }
    var activeExtensionTab: (any BrowserTab)? { get }
    func isPinned(_ tab: any BrowserTab) -> Bool
    func activate(_ tab: any BrowserTab)
    func close(_ tab: any BrowserTab)
    /// In screen coordinates.
    var extensionFrame: CGRect { get }
    var extensionScreenFrame: CGRect { get }
    var isMinimized: Bool { get }
    var isFullScreen: Bool { get }
    func focusWindow()
    func closeWindow()
}

/// What the app does for extensions: its windows, opening tabs, and asking the user.
@MainActor
public protocol ExtensionHost: AnyObject {
    /// Open windows, the focused one first.
    var extensionWindows: [any ExtensionWindow] { get }
    var focusedExtensionWindow: (any ExtensionWindow)? { get }
    /// Opens a tab in `window`, or the focused window when nil. Nil when it couldn't.
    func openTab(url: URL?, in window: (any ExtensionWindow)?, active: Bool, pinned: Bool) -> (any BrowserTab)?
    func openWindow(urls: [URL], focused: Bool) -> (any ExtensionWindow)?
    /// Asks whether `extensionName` may have more permissions or sites. True allows all of them.
    func askPermission(extensionName: String, permissions: Set<String>, matchPatterns: Set<String>) async -> Bool
    /// Where to show an extension's popup when the extension opens it itself: its button in the focused window.
    func actionAnchor(forExtension id: String) -> NSView?
}

/// An engine that runs Web Extensions. Optional: the UI checks for it with `as?`.
@MainActor
public protocol ExtensionEngine: BrowserEngine {
    /// False on systems too old for extensions. The other calls then do nothing or throw.
    var supportsExtensions: Bool { get }
    var extensionHost: (any ExtensionHost)? { get set }
    /// Called when an extension's permissions change, so they can be saved.
    var onExtensionPermissionsChanged: (@MainActor (String, ExtensionPermissions) -> Void)? { get set }
    /// Reads the extension in `folder` without running it.
    func readExtension(at folder: URL) async throws -> ExtensionDetails
    /// Starts the extension in `folder` with the permissions the user gave it.
    func loadExtension(id: String, at folder: URL, permissions: ExtensionPermissions) async throws -> any BrowserExtension
    func unloadExtension(id: String)
    /// The user clicked the extension's button: shows its popup under `anchor`, or tells the extension.
    func performAction(of browserExtension: any BrowserExtension, in tab: (any BrowserTab)?, anchor: NSView)
    func windowDidOpen(_ window: any ExtensionWindow)
    func windowDidClose(_ window: any ExtensionWindow)
    func windowDidFocus(_ window: (any ExtensionWindow)?)
    func tabDidActivate(_ tab: any BrowserTab, previous: (any BrowserTab)?)
}
