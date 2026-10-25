import Foundation

/// Whether pages can be opened in Web Inspector: Inspect Element in the page's context menu and
/// View > Developer > Show Web Inspector. Off until you turn it on in Settings > General.
public struct DeveloperToolsSettings {
    public static let key = "ShowDeveloperTools"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
