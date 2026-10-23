import AppKit
import Archive
import Sidebar
import SidebarModel

/// Archives inactive unpinned tabs at launch, every 5 minutes, and when the Mac wakes.
@MainActor
final class ArchiveSweeper {
    static let intervalKey = "ArchiveAfterHours"
    static let defaultHours = 12
    static let choices = [12, 24, 7 * 24, 30 * 24, 0]

    private let sidebar: SidebarStore
    private let archive: ArchiveStore
    private let protectedItems: () -> Set<ItemID>
    private var timer: Timer?
    private var wakeObserver: (any NSObjectProtocol)?

    init(sidebar: SidebarStore, archive: ArchiveStore, protecting protectedItems: @escaping () -> Set<ItemID>) {
        self.sidebar = sidebar
        self.archive = archive
        self.protectedItems = protectedItems
    }

    /// Hours before an unpinned tab is archived. 0 means never.
    static var hours: Int {
        get { UserDefaults.standard.object(forKey: intervalKey) as? Int ?? defaultHours }
        set { UserDefaults.standard.set(newValue, forKey: intervalKey) }
    }

    func start() {
        sweep()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.sweep() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.sweep() }
        }
    }

    func sweep() {
        let hours = Self.hours
        guard hours > 0 else { return }
        archiveInactiveTabs(sidebar: sidebar, archive: archive, now: .now, after: TimeInterval(hours) * 3600, protecting: protectedItems())
    }
}
