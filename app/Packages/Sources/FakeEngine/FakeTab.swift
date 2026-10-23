import AppKit
import BrowserEngine
import Observation

/// A tab that records what it's asked to do. Tests drive page events through the `simulate` methods.
@MainActor
@Observable
public final class FakeTab: BrowserTab {
    public let id = TabID.make()
    public private(set) var state = TabState.blank
    public let contentView = NSView()
    @ObservationIgnored public weak var delegate: (any BrowserTabDelegate)?

    public private(set) var loadedURLs: [URL] = []
    public private(set) var isClosed = false

    /// Strong on purpose: tests often keep only the tab. The cycle with `FakeEngine.madeTabs` is fine for a test double.
    @ObservationIgnored private let engine: FakeEngine
    private var history: [URL] = []
    private var index = -1

    init(engine: FakeEngine) {
        self.engine = engine
    }

    public func load(_ url: URL) {
        loadedURLs.append(url)
        history = Array(history.prefix(index + 1)) + [url]
        index = history.count - 1
        state.title = nil
        state.isLoading = true
        state.estimatedProgress = 0
        updateHistoryState()
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

    public func finishLoading(title: String?) {
        state.title = title
        state.isLoading = false
        state.estimatedProgress = 1
    }

    @discardableResult
    public func simulateOpen(url: URL?, disposition: NewTabDisposition) -> FakeTab {
        let newTab = engine.makeFakeTab(url: url)
        delegate?.tab(self, didOpen: newTab, disposition: disposition)
        return newTab
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
