import AppKit
import BrowserEngine
import Observation

/// A tab that records what it's asked to do. Tests drive page events through the `simulate` methods.
@MainActor
@Observable
public final class FakeTab: BrowserTab {
    public let id = TabID.make()
    public let profile: ProfileIdentifier
    public private(set) var state = TabState.blank {
        didSet { delegate?.tabStateDidChange(self) }
    }
    public let contentView = NSView()
    @ObservationIgnored public weak var delegate: (any BrowserTabDelegate)?

    public private(set) var loadedURLs: [URL] = []
    public private(set) var isClosed = false
    /// What `isPlayingMedia()` answers.
    @ObservationIgnored public var isPlayingMediaForTesting = false
    /// What `hasUnsavedState()` answers.
    @ObservationIgnored public var hasUnsavedStateForTesting = false
    /// What `find` answers, and every search it was asked for.
    @ObservationIgnored public var findResult = false
    @ObservationIgnored public private(set) var finds: [(String, Bool)] = []
    /// Whether a video plays, for `enterPictureInPicture`.
    @ObservationIgnored public var isPlayingVideoForTesting = false
    /// True while `enterPictureInPicture` has the video floating.
    public private(set) var isInPictureInPicture = false
    /// What `thumbnail(width:)` answers.
    @ObservationIgnored public var thumbnailForTesting: NSImage?

    /// Strong on purpose: tests often keep only the tab. The cycle with `FakeEngine.madeTabs` is fine for a test double.
    @ObservationIgnored private let engine: FakeEngine
    private var history: [URL] = []
    private var index = -1

    init(engine: FakeEngine, profile: ProfileIdentifier) {
        self.engine = engine
        self.profile = profile
    }

    public func load(_ url: URL) {
        loadedURLs.append(url)
        history = Array(history.prefix(index + 1)) + [url]
        index = history.count - 1
        state.title = nil
        state.faviconURL = nil
        state.isReaderAvailable = false
        state.isShowingReader = false
        state.isLoading = true
        state.estimatedProgress = 0
        updateHistoryState()
    }

    public func snapshot() -> TabSnapshot {
        TabSnapshot(url: state.url, title: state.title, sessionState: nil)
    }

    public func hasUnsavedState() async -> Bool { hasUnsavedStateForTesting }

    public func find(_ text: String, backwards: Bool) async -> Bool {
        finds.append((text, backwards))
        return findResult
    }

    public func clearFind() {}

    public func showReader() async -> Bool {
        guard state.isReaderAvailable else { return false }
        state.isShowingReader = true
        return true
    }

    public func hideReader() {
        state.isShowingReader = false
    }

    public func enterPictureInPicture() async -> Bool {
        guard isPlayingVideoForTesting, !isInPictureInPicture else { return false }
        isInPictureInPicture = true
        return true
    }

    public func exitPictureInPicture() {
        isInPictureInPicture = false
    }

    public func thumbnail(width: CGFloat) async -> NSImage? { thumbnailForTesting }

    /// The page turns out to be an article, or not, as a page does once it has loaded.
    public func simulateArticle(_ isArticle: Bool) {
        state.isReaderAvailable = isArticle
    }

    public func simulateChooseFiles(multiple: Bool, directories: Bool) async -> [URL]? {
        guard let delegate else { return nil }
        return await delegate.tab(self, chooseFiles: multiple, allowsDirectories: directories)
    }

    public func simulateCaptureRequest(_ media: MediaCapture, origin: URL) async -> Bool {
        guard let delegate else { return false }
        return await delegate.tab(self, mayCapture: media, forOrigin: origin)
    }

    public func isPlayingMedia() async -> Bool {
        isPlayingMediaForTesting
    }

    public func setUsingCameraOrMicrophone(_ on: Bool) {
        state.isUsingCameraOrMicrophone = on
    }

    public func goBack() {
        guard index > 0 else { return }
        index -= 1
        updateHistoryState()
    }

    public func goForward() {
        guard index < history.count - 1 else { return }
        index += 1
        updateHistoryState()
    }

    public func reload() {
        guard state.url != nil else { return }
        state.isLoading = true
    }

    public func stopLoading() {
        state.isLoading = false
    }

    public func close() {
        isClosed = true
        state.isLoading = false
    }

    // MARK: Test hooks

    public func finishLoading(title: String?, faviconURL: URL? = nil) {
        state.title = title
        state.faviconURL = faviconURL
        state.isLoading = false
        state.estimatedProgress = 1
    }

    @discardableResult
    public func simulateOpen(url: URL?, disposition: NewTabDisposition) -> FakeTab {
        let newTab = engine.makeFakeTab(url: url, profile: profile)
        delegate?.tab(self, didOpen: newTab, disposition: disposition)
        return newTab
    }

    /// A plain click on a link to `url`: loads it unless the delegate takes it elsewhere.
    public func simulateLinkClick(to url: URL, shiftKey: Bool = false) {
        if delegate?.tab(self, shouldFollowLinkTo: url, shiftKey: shiftKey) ?? true {
            load(url)
        }
    }

    public func simulateRequestClose() {
        delegate?.tabDidRequestClose(self)
    }

    public func simulateDialog(_ dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        guard let delegate else { return .dismissed }
        return await delegate.tab(self, runDialog: dialog)
    }

    private func updateHistoryState() {
        state.url = history.indices.contains(index) ? history[index] : nil
        state.canGoBack = index > 0
        state.canGoForward = index < history.count - 1
    }
}
