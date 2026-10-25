import AppKit
import OSLog
import RemoteSettings

/// Applies the remote settings: the last good copy at launch, then a fresh one once a day. Each time they
/// change, their message shows if this version hasn't shown it.
@MainActor
final class RemoteSettingsController {
    private let store: RemoteSettingsStore
    /// Returns false when the message couldn't show yet, such as with no window open, so it's tried again later.
    private let present: (RemoteMessage) -> Bool
    private let ledger = RemoteMessageLedger()
    private var timer: Timer?

    /// Nil while Sela carries the placeholder public key, so nothing is fetched or used until a real key is in place.
    init?(folder: URL, present: @escaping (RemoteMessage) -> Bool) {
        guard let signature = RemoteSettingsSignature() else {
            Logger(subsystem: "app.sela", category: "RemoteSettings")
                .notice("Remote settings are off because RemoteSettingsSignature.publicKey is still the placeholder.")
            return nil
        }
        store = RemoteSettingsStore(folder: folder, signature: signature)
        self.present = present
        RemoteSettings.current = store.settings
    }

    /// Checks now and every 6 hours. The store only downloads once a day.
    func start() {
        showMessageIfDue()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func refresh() async {
        guard await store.refresh() else { return }
        RemoteSettings.current = store.settings
        showMessageIfDue()
    }

    private func showMessageIfDue() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard let message = ledger.messageToShow(in: store.settings, appVersion: version), present(message) else { return }
        ledger.markShown(message)
    }
}
