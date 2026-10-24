import Foundation

public enum NewTabDisposition: Sendable {
    case foreground
    case background
}

/// Receives requests a page makes that the UI has to handle.
@MainActor
public protocol BrowserTabDelegate: AnyObject {
    /// The page opened a tab: a popup, a `target=_blank` link, or a Cmd-click.
    func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition)
    /// Something in the tab's `state` changed.
    func tabStateDidChange(_ tab: any BrowserTab)
    /// The page called `window.close()`.
    func tabDidRequestClose(_ tab: any BrowserTab)
    /// The page called `alert`, `confirm` or `prompt`. The page waits until this returns.
    func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult
    /// The user clicked a link that would load in this tab. Return false when the delegate has opened it
    /// somewhere else, such as in Peek, so the tab stays where it is.
    func tab(_ tab: any BrowserTab, shouldFollowLinkTo url: URL, shiftKey: Bool) -> Bool
    /// The page wants files for an upload. Nil means the user cancelled.
    func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]?
    /// The page wants the camera, the microphone or both. True allows it.
    func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool
}

extension BrowserTabDelegate {
    public func tab(_ tab: any BrowserTab, shouldFollowLinkTo url: URL, shiftKey: Bool) -> Bool { true }
    public func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? { nil }
    public func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool { false }
}
