import Foundation

/// The short notes shown once after an update, read from the bundled `WhatsNew.json`, which is keyed by version:
/// `{ "0.1.5": ["First note", "Second note"] }`. Release notes can be copied in as they are.
public struct WhatsNewNotes: Equatable, Sendable {
    /// How many notes a version shows at most. Longer lists are cut, so the window stays small.
    public static let maximumBullets = 6

    public var bullets: [String: [String]]

    public init(bullets: [String: [String]]) {
        self.bullets = bullets
    }

    /// Throws when the file isn't an object of version strings to lists of strings.
    public init(json data: Data) throws {
        bullets = try JSONDecoder().decode([String: [String]].self, from: data)
    }

    /// The notes for `version`, blank ones dropped and cut to `maximumBullets`. Nil when there are none.
    public func bullets(for version: String) -> [String]? {
        let kept = (bullets[version] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maximumBullets)
        return kept.isEmpty ? nil : Array(kept)
    }
}

/// Whether to show the notes on this launch.
public enum WhatsNewDecision {
    /// Shows when the version changed since the notes were last shown and there's something to say. On a first
    /// install nothing is shown, and the version is simply recorded. Someone whose Sela predates the notes,
    /// so never recorded a version, sees them once their data shows they've run Sela before.
    public static func shouldShow(current: String, lastShown: String?, isFirstInstall: Bool, hasNotes: Bool) -> Bool {
        guard hasNotes, lastShown != current else { return false }
        if lastShown == nil { return !isFirstInstall }
        return true
    }
}

/// The version the notes were last shown for, or recorded as seen, in `UserDefaults`.
public struct WhatsNewRecord {
    public static let key = "WhatsNewShownForVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var shownVersion: String? {
        get { defaults.string(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
