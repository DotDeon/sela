import Foundation
import Testing
import RemoteSettings

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-messages-\(UUID().uuidString)")!
}

private func settings(minimum: String? = nil, maximum: String? = nil, id: String = "news") -> RemoteSettings {
    RemoteSettings(message: RemoteMessage(id: id, text: "Sela 0.2 is out", minimumVersion: minimum.flatMap(AppVersion.init), maximumVersion: maximum.flatMap(AppVersion.init)))
}

@Test(arguments: [
    (nil, nil, "0.1.3", true),
    ("0.1.3", nil, "0.1.3", true),
    ("0.1.4", nil, "0.1.3", false),
    (nil, "0.1.3", "0.1.3", true),
    (nil, "0.1.2", "0.1.3", false),
    ("0.1", "0.2", "0.1.10", true),
    ("0.1", "0.2", "0.2.1", false),
    ("0.1.0", nil, "dev", false),
    (nil, nil, "dev", true),
] as [(String?, String?, String, Bool)])
func messagesShowOnlyToTheirVersions(minimum: String?, maximum: String?, version: String, shows: Bool) {
    let ledger = RemoteMessageLedger(defaults: freshDefaults())
    #expect((ledger.messageToShow(in: settings(minimum: minimum, maximum: maximum), appVersion: version) != nil) == shows)
}

@Test func aMessageShowsOnce() throws {
    let ledger = RemoteMessageLedger(defaults: freshDefaults())
    let message = try #require(ledger.messageToShow(in: settings(), appVersion: "0.1.3"))
    ledger.markShown(message)
    #expect(ledger.messageToShow(in: settings(), appVersion: "0.1.3") == nil)
    #expect(ledger.messageToShow(in: settings(id: "later"), appVersion: "0.1.3") != nil)
}

@Test func versionsCompareByNumber() throws {
    #expect(try #require(AppVersion("0.1.10")) > #require(AppVersion("0.1.9")))
    #expect(AppVersion("1.2") == AppVersion("1.2.0"))
    #expect(AppVersion("1..2") == nil)
    #expect(AppVersion("1.2-beta") == nil)
    #expect(AppVersion("") == nil)
}

private extension Feature {
    static let offByDefault = Feature("offByDefault")
    static let onByDefault = Feature("onByDefault", isOnByDefault: true)
}

@Test func featuresFollowTheirBuiltInDefault() {
    #expect(!FeatureFlags.isOn(.offByDefault, remote: .empty, defaults: freshDefaults()))
    #expect(FeatureFlags.isOn(.onByDefault, remote: .empty, defaults: freshDefaults()))
}

@Test func remoteSettingsSwitchFeatures() {
    let remote = RemoteSettings(features: ["offByDefault": true, "onByDefault": false])
    #expect(FeatureFlags.isOn(.offByDefault, remote: remote, defaults: freshDefaults()))
    #expect(!FeatureFlags.isOn(.onByDefault, remote: remote, defaults: freshDefaults()))
}

/// Launch arguments arrive as text.
@Test func aLaunchArgumentWins() {
    let defaults = freshDefaults()
    defaults.set("YES", forKey: "Feature.offByDefault")
    #expect(FeatureFlags.isOn(.offByDefault, remote: RemoteSettings(features: ["offByDefault": false]), defaults: defaults))
}
