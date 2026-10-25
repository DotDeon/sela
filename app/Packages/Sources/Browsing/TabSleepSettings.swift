import Foundation
import RemoteSettings

/// How long a tab goes unseen before it sleeps, stored in `UserDefaults`. Until you choose, the remote
/// settings' default applies when it's one of the choices.
public struct TabSleepSettings {
    /// Minutes, offered in this order. 0 means never.
    public static let choices = [5, 15, 60, 0]
    public static let key = "SleepTabsAfterMinutes"
    /// A launch argument for measuring runs, such as `-SleepTabsAfterSeconds 60`. Wins over the setting.
    static let secondsOverrideKey = "SleepTabsAfterSeconds"
    static let defaultMinutes = 15

    private let defaults: UserDefaults
    private let remote: RemoteSettings

    public init(defaults: UserDefaults = .standard, remote: RemoteSettings = .current) {
        self.defaults = defaults
        self.remote = remote
    }

    /// Until you choose, picking the value already in use stores nothing, so a later change to the default still reaches you.
    public var minutes: Int {
        get {
            if let stored { return stored }
            if let remote = remote.defaults.tabSleepMinutes, Self.choices.contains(remote) { return remote }
            return Self.defaultMinutes
        }
        nonmutating set {
            if stored == nil, newValue == minutes { return }
            defaults.set(newValue, forKey: Self.key)
        }
    }

    private var stored: Int? {
        guard let stored = defaults.object(forKey: Self.key) as? Int, Self.choices.contains(stored) else { return nil }
        return stored
    }

    /// Nil when tabs never sleep.
    public var interval: TimeInterval? {
        // `integer(forKey:)` also reads launch arguments, which arrive as text.
        let seconds = defaults.integer(forKey: Self.secondsOverrideKey)
        if seconds > 0 {
            return TimeInterval(seconds)
        }
        return minutes == 0 ? nil : TimeInterval(minutes * 60)
    }
}
