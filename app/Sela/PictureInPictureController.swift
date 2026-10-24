import AppKit
import BrowserEngine
import Browsing
import SidebarUI

/// Floats a window's playing video in picture in picture when you switch to another tab or away from the window,
/// and brings it back when you return. Settings > General turns it off.
@MainActor
final class PictureInPictureController {
    private let model: BrowserWindowModel
    private weak var window: NSWindow?
    private var decisions = AutoPictureInPicture(isEnabled: PictureInPictureSettings().isEnabled)
    /// Lives as long as the window, so its observers are never removed. They hold it weakly.
    private var observers: [NSObjectProtocol] = []

    init(model: BrowserWindowModel, window: NSWindow) {
        self.model = model
        self.window = window
        let center = NotificationCenter.default
        let windowChanges = [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                             NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification]
        let appChanges = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
        for name in windowChanges {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        for name in appChanges {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        keepObserving { [weak self] in self?.update() }
    }

    /// The selected tab, every pane of its split, and Peek.
    private var visibleTabs: [any BrowserTab] {
        let ids = model.selectedSplit?.paneIDs ?? model.selectedItemID.map { [$0] } ?? []
        return ids.compactMap(model.liveTab(for:)) + [model.peekTab].compactMap { $0 }
    }

    private var isWindowActive: Bool {
        guard let window else { return false }
        return NSApp.isActive && window.isMainWindow && window.isVisible && !window.isMiniaturized
    }

    private func update() {
        let visible = Set(visibleTabs.map(\.id))
        let live = Set(model.liveTabsInOrder.map(\.id)).union(visible)
        // Tabs that closed or slept since the last look are gone for good.
        for id in decisions.watched.union(decisions.entering).union(decisions.floating) where !live.contains(id) {
            decisions.forget(id)
        }
        decisions.isEnabled = PictureInPictureSettings().isEnabled
        perform(decisions.update(visible: visible, windowIsActive: isWindowActive))
    }

    private func perform(_ steps: [AutoPictureInPicture.Step]) {
        for step in steps {
            switch step {
            case .enter(let id):
                guard let tab = tab(id) else {
                    decisions.forget(id)
                    continue
                }
                Task { [weak self] in
                    let floated = await tab.enterPictureInPicture()
                    guard let self else { return }
                    perform(decisions.didEnter(id, floated: floated))
                }
            case .exit(let id):
                tab(id)?.exitPictureInPicture()
            }
        }
    }

    private func tab(_ id: TabID) -> (any BrowserTab)? {
        (model.liveTabsInOrder + [model.peekTab].compactMap { $0 }).first { $0.id == id }
    }
}
