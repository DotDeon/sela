import AppKit
import Browsing

/// Puts unused tabs to sleep in every window: once a minute for tabs past the chosen time,
/// and straight away for every background tab when macOS warns that memory is low.
@MainActor
final class TabSleeper {
    private let models: () -> [BrowserWindowModel]
    private var timer: Timer?
    private var memoryPressure: DispatchSourceMemoryPressure?

    init(models: @escaping () -> [BrowserWindowModel]) {
        self.models = models
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sleepUnusedTabs() }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.sleepEveryBackgroundTab() }
        }
        source.resume()
        memoryPressure = source
    }

    /// Sleeps tabs past the chosen time. Called by the timer and after the setting changes.
    func sleepUnusedTabs() async {
        guard let interval = TabSleepSettings().interval else { return }
        for model in models() { await model.sleepTabs(unusedFor: interval) }
    }

    private func sleepEveryBackgroundTab() async {
        for model in models() { await model.sleepTabs(unusedFor: 0) }
    }
}
