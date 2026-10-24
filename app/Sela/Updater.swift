import AppKit
import Sparkle

/// Keeps Sela up to date with Sparkle. It checks the feed attached to the newest GitHub release
/// once a day, and asks before installing. Every update is signed with the key whose public half
/// is SUPublicEDKey in Info.plist, so a download that doesn't match is refused.
@MainActor
final class Updater: NSObject {
    private let controller: SPUStandardUpdaterController

    /// Measuring runs with `-SelaDataFolder` never check, so they stay offline and repeatable.
    init(enabled: Bool) {
        controller = SPUStandardUpdaterController(startingUpdater: enabled, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkNow() {
        controller.checkForUpdates(nil)
    }
}
