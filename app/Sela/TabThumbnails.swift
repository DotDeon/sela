import AppKit
import Browsing
import Observation
import SidebarModel
import SidebarUI

/// The last picture of each tab's page in one window, for the tab overview. A tab is pictured as you leave it
/// and a moment after you arrive, so a tab that has since gone to sleep still has the picture from then.
@MainActor
@Observable
final class TabThumbnails {
    static let width: CGFloat = 480

    private(set) var images: [ItemID: NSImage] = [:]
    @ObservationIgnored private let model: BrowserWindowModel
    @ObservationIgnored private var shown: ItemID?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    init(model: BrowserWindowModel) {
        self.model = model
        keepObserving { [weak self] in self?.selectionChanged() }
    }

    /// Pictures every live tab that can be drawn, keeping the old picture of any that can't.
    func refresh(_ ids: [ItemID]) async {
        for id in ids { await capture(id) }
    }

    func capture(_ id: ItemID) async {
        guard let tab = model.liveTab(for: id), let image = await tab.thumbnail(width: Self.width) else { return }
        images[id] = image
    }

    private func selectionChanged() {
        let selected = model.selectedItemID
        guard selected != shown else { return }
        let previous = shown
        shown = selected
        if let previous { Task { await capture(previous) } }
        forgetRemovedTabs()
        settleTask?.cancel()
        guard let selected else { return }
        // Long enough for the page to draw after it's swapped in.
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, model.selectedItemID == selected else { return }
            await capture(selected)
        }
    }

    private func forgetRemovedTabs() {
        let document = model.sidebar.document
        let gone = images.keys.filter { document.item($0) == nil }
        for id in gone { images[id] = nil }
    }
}
