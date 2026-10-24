import Foundation

/// What a page needs to come back exactly where it was after its tab was put to sleep.
public struct TabSnapshot: Equatable, Sendable {
    public var url: URL?
    public var title: String?
    /// The engine's own record of history and scroll position. Only the engine that made it can read it.
    public var sessionState: Data?

    public init(url: URL?, title: String?, sessionState: Data?) {
        self.url = url
        self.title = title
        self.sessionState = sessionState
    }
}
