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
}
