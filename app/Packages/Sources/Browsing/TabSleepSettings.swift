import Foundation

/// How long a tab goes unseen before it sleeps, stored in `UserDefaults`.
public struct TabSleepSettings {
    /// Minutes, offered in this order. 0 means never.
    public static let choices = [5, 15, 60, 0]
    public static let key = "SleepTabsAfterMinutes"
    /// A launch argument for measuring runs, such as `-SleepTabsAfterSeconds 60`. Wins over the setting.
    static let secondsOverrideKey = "SleepTabsAfterSeconds"
    static let defaultMinutes = 15

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var minutes: Int {
        get {
            guard let stored = defaults.object(forKey: Self.key) as? Int, Self.choices.contains(stored) else { return Self.defaultMinutes }
            return stored
        }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
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
