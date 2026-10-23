import AppKit
import Observation

public struct TabID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }

    public static func make() -> TabID { TabID(rawValue: UUID()) }

    public var description: String { rawValue.uuidString }
}

/// What the UI shows about a tab.
public struct TabState: Equatable, Sendable {
    public var url: URL?
    public var title: String?
    public var isLoading: Bool
    public var estimatedProgress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool

    public init(url: URL?, title: String?, isLoading: Bool, estimatedProgress: Double, canGoBack: Bool, canGoForward: Bool) {
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    public static let blank = TabState(url: nil, title: nil, isLoading: false, estimatedProgress: 0, canGoBack: false, canGoForward: false)
}

/// One live web page. Implementations are `@Observable`, so reading `state` inside observation tracking sees changes.
@MainActor
public protocol BrowserTab: AnyObject, Observable {
    var id: TabID { get }
    var state: TabState { get }
    /// The view that draws the page. The UI places it; the tab owns it.
    var contentView: NSView { get }
    var delegate: (any BrowserTabDelegate)? { get set }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    /// Stops the page and releases its content. The tab isn't used again.
    func close()
}
