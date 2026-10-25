import BrowserEngine
import Foundation
import RemoteSettings

/// Decides when a window's videos float in picture in picture: a tab you leave while its video plays floats it,
/// and the video comes back when you return. Leaving means selecting another tab or the window losing focus.
/// The window carries out the steps and reports back whether a video floated.
public struct AutoPictureInPicture: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Float the tab's playing video, if it has one, and report the result to `didEnter`.
        case enter(TabID)
        /// Bring the tab's floated video back.
        case exit(TabID)
    }

    /// Off, tabs you leave aren't floated. Videos already floating still come back.
    public var isEnabled: Bool
    /// The tabs you can see now: on screen in a focused window.
    public private(set) var watched: Set<TabID> = []
    /// Tabs asked to float that haven't answered yet.
    public private(set) var entering: Set<TabID> = []
    /// Tabs whose video Sela floated.
    public private(set) var floating: Set<TabID> = []

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Call whenever the tabs on screen change, or the window gains or loses focus.
    public mutating func update(visible: Set<TabID>, windowIsActive: Bool) -> [Step] {
        let nowWatched = windowIsActive ? visible : []
        let left = watched.subtracting(nowWatched)
        let returned = floating.union(entering).intersection(nowWatched)
        watched = nowWatched
        var steps: [Step] = []
        for id in returned.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            // A tab still answering is brought back once it does, in `didEnter`.
            if floating.remove(id) != nil { steps.append(.exit(id)) }
            entering.remove(id)
        }
        guard isEnabled else { return steps }
        for id in left.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) where !floating.contains(id) {
            entering.insert(id)
            steps.append(.enter(id))
        }
        return steps
    }

    /// Records whether a tab's video floated. Returns `.exit` when you came back to the tab while it was floating it.
    public mutating func didEnter(_ id: TabID, floated: Bool) -> [Step] {
        guard floated else {
            entering.remove(id)
            return []
        }
        if entering.remove(id) != nil {
            floating.insert(id)
            return []
        }
        return watched.contains(id) ? [.exit(id)] : []
    }

    /// Forgets a tab that closed or went to sleep.
    public mutating func forget(_ id: TabID) {
        watched.remove(id)
        entering.remove(id)
        floating.remove(id)
    }
}

/// Whether videos float when you leave their tab, stored in `UserDefaults`. Until you choose, the remote
/// settings' default applies, and without one it's on.
public struct PictureInPictureSettings {
    public static let key = "AutoPictureInPicture"

    private let defaults: UserDefaults
    private let remote: RemoteSettings

    public init(defaults: UserDefaults = .standard, remote: RemoteSettings = .current) {
        self.defaults = defaults
        self.remote = remote
    }

    /// Until you choose, picking the value already in use stores nothing, so a later change to the default still reaches you.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? remote.defaults.autoPictureInPicture ?? true }
        nonmutating set {
            if defaults.object(forKey: Self.key) as? Bool == nil, newValue == isEnabled { return }
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
