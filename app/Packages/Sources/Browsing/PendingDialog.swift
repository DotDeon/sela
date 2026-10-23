import BrowserEngine
import Foundation

/// A JavaScript dialog a page is waiting on.
public struct PendingDialog: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tabID: TabID
    public let dialog: JavaScriptDialog
}
