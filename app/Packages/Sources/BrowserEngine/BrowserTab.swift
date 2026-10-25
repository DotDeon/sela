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
    /// The page's icon, once the page has finished loading.
    public var faviconURL: URL?
    /// True while the page has the camera or microphone, even muted.
    public var isUsingCameraOrMicrophone: Bool
    /// True when the page looks like an article, so reader mode is worth offering.
    public var isReaderAvailable: Bool
    /// True while the tab shows its page in reader mode.
    public var isShowingReader: Bool
    /// How much the page is scaled: 1 is actual size, 1.5 is 150 percent.
    public var pageZoom: Double
    /// True while the page makes sound, or would if it weren't muted.
    public var isPlayingAudio: Bool
    /// True while the tab's sound is turned off with `setMuted`.
    public var isMuted: Bool

    public init(url: URL?, title: String?, isLoading: Bool, estimatedProgress: Double, canGoBack: Bool, canGoForward: Bool, faviconURL: URL? = nil,
                isUsingCameraOrMicrophone: Bool = false, isReaderAvailable: Bool = false, isShowingReader: Bool = false, pageZoom: Double = 1,
                isPlayingAudio: Bool = false, isMuted: Bool = false) {
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.faviconURL = faviconURL
        self.isUsingCameraOrMicrophone = isUsingCameraOrMicrophone
        self.isReaderAvailable = isReaderAvailable
        self.isShowingReader = isShowingReader
        self.pageZoom = pageZoom
        self.isPlayingAudio = isPlayingAudio
        self.isMuted = isMuted
    }

    public static let blank = TabState(url: nil, title: nil, isLoading: false, estimatedProgress: 0, canGoBack: false, canGoForward: false)
}

/// One live web page. Implementations are `@Observable`, so reading `state` inside observation tracking sees changes.
@MainActor
public protocol BrowserTab: AnyObject, Observable {
    var id: TabID { get }
    /// Whose website data the page uses. It never changes: moving a page to another profile means a new tab.
    var profile: ProfileIdentifier { get }
    var state: TabState { get }
    /// The view that draws the page. The UI places it; the tab owns it.
    var contentView: NSView { get }
    var delegate: (any BrowserTabDelegate)? { get set }

    func load(_ url: URL)
    /// The page's address, title and history, for waking it later with `BrowserEngine.makeTab(restoring:)`.
    func snapshot() -> TabSnapshot
    /// True while the page plays audio or video.
    func isPlayingMedia() async -> Bool
    /// True when unloading would lose something: edited form fields, or a page that came from a submitted form,
    /// which waking would send again.
    func hasUnsavedState() async -> Bool
    /// Selects the next match for `text`, ignoring case and wrapping around. False when the page has no match.
    func find(_ text: String, backwards: Bool) async -> Bool
    /// Removes the selection a find left.
    func clearFind()
    /// Shows the page's article in a plain, readable layout in the same tab. False when no article was found.
    /// Loading another page goes back to the page itself.
    func showReader() async -> Bool
    /// Goes back from reader mode to the page itself.
    func hideReader()
    /// The page's declared language and a sample of its text. Nil when there's no page to read.
    func languageSample() async -> PageLanguageSample?
    /// The page's visible text, one segment per text node, skipping code, form fields and anything being edited.
    /// The page keeps watching for text that appears later and hands it to `onNewText`, until `restorePageText`.
    func collectPageText(onNewText: @escaping @MainActor ([TextSegment]) -> Void) async -> [TextSegment]
    /// Writes text back into the nodes `collectPageText` numbered, keeping the layout around them.
    func replacePageText(_ segments: [TextSegment])
    /// Puts every text node back as it was and stops watching for new text.
    func restorePageText()
    /// Moves the video playing in the page into a floating picture in picture window. False when no video is
    /// playing, the page turned picture in picture off, or the video already floats.
    func enterPictureInPicture() async -> Bool
    /// Brings back a video that `enterPictureInPicture` moved. Leaves a video the user moved alone.
    func exitPictureInPicture()
    /// A picture of what the page shows, `width` points wide. Nil when there's nothing to draw.
    func thumbnail(width: CGFloat) async -> NSImage?
    /// Scales the page, and everything in it, to `zoom` times its actual size. `state.pageZoom` follows.
    func setPageZoom(_ zoom: Double)
    /// Turns the tab's sound off, or back on. `state.isMuted` follows. Not kept between launches.
    func setMuted(_ muted: Bool)
    /// Opens Web Inspector on the page. Does nothing while the engine isn't inspectable.
    func showWebInspector()
    /// Prints what the page shows, the reader when it's on, through the standard print panel.
    /// Nil when there's no page to print.
    func printOperation(with info: NSPrintInfo) -> NSPrintOperation?
    /// What the page shows as a PDF, one tall page at the page's width.
    func pdf() async throws -> Data
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    /// Stops the page and releases its content. The tab isn't used again.
    func close()
}
