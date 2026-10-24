import Foundation
import Testing
import Browsing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-sleep-\(UUID().uuidString)")!
}

@Test func defaultsToFifteenMinutes() {
    let settings = TabSleepSettings(defaults: freshDefaults())
    #expect(settings.minutes == 15)
    #expect(settings.interval == 900)
}

@Test func neverMeansNoInterval() {
    var settings = TabSleepSettings(defaults: freshDefaults())
    settings.minutes = 0
    #expect(settings.interval == nil)
    #expect(settings.minutes == 0)
}

@Test func unknownValuesFallBack() {
    let defaults = freshDefaults()
    defaults.set(7, forKey: TabSleepSettings.key)
    #expect(TabSleepSettings(defaults: defaults).minutes == 15)
}

@Test func secondsOverrideWins() {
    let defaults = freshDefaults()
    defaults.set(30, forKey: "SleepTabsAfterSeconds")
    #expect(TabSleepSettings(defaults: defaults).interval == 30)
}

/// Launch arguments arrive as text.
@Test func secondsOverrideFromALaunchArgument() {
    let defaults = freshDefaults()
    defaults.set("45", forKey: "SleepTabsAfterSeconds")
    #expect(TabSleepSettings(defaults: defaults).interval == 45)
}
