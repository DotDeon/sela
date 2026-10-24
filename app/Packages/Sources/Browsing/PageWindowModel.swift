import BrowserEngine
import Observation

/// What a window's dialog sheet and find bar need from it: the page in front and the dialogs it's waiting on.
@MainActor
public protocol PageWindowModel: AnyObject, Observable {
    var selectedTab: (any BrowserTab)? { get }
    /// The oldest dialog from the page in front.
    var dialogForSelectedTab: PendingDialog? { get }
    func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult)
}
