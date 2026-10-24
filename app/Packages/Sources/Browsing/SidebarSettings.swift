import Foundation

/// Whether the sidebar stays hidden until the pointer reaches the window's left edge.
/// New windows and the next launch follow the last choice.
public struct SidebarSettings {
    public static let key = "SidebarHidden"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isHidden: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
