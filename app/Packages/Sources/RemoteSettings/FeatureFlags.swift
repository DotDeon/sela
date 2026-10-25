import Foundation

/// A named switch with a built-in default, so a feature can ship turned off and be turned on from the
/// remote settings' `features`. Declare one as `extension Feature { static let newThing = Feature("newThing") }`.
public struct Feature: Hashable, Sendable {
    public let name: String
    public let isOnByDefault: Bool

    public init(_ name: String, isOnByDefault: Bool = false) {
        self.name = name
        self.isOnByDefault = isOnByDefault
    }
}

public enum FeatureFlags {
    /// A launch argument such as `-Feature.newThing YES` wins, for trying a feature out. Then the remote
    /// settings, then the built-in default.
    public static func isOn(_ feature: Feature, remote: RemoteSettings = .current, defaults: UserDefaults = .standard) -> Bool {
        let key = "Feature.\(feature.name)"
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return remote.features[feature.name] ?? feature.isOnByDefault
    }
}
