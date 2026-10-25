import Foundation

/// The sizes a page can be shown at, Safari's steps, and moving between them.
public enum PageZoom {
    /// From 50 to 300 percent. 1 is actual size.
    public static let steps: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The next step up from `zoom`, or the largest when there isn't one.
    public static func zoomedIn(from zoom: Double) -> Double {
        steps.first { $0 > zoom + tolerance } ?? steps.last!
    }

    /// The next step down from `zoom`, or the smallest when there isn't one.
    public static func zoomedOut(from zoom: Double) -> Double {
        steps.last { $0 < zoom - tolerance } ?? steps.first!
    }

    /// True at actual size.
    public static func isActualSize(_ zoom: Double) -> Bool {
        abs(zoom - 1) < tolerance
    }

    /// "150%" for 1.5.
    public static func percentText(_ zoom: Double) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    /// Zoom levels within this much of each other count as the same, so floating point noise never skips a step.
    private static let tolerance = 0.001
}

/// The zoom level each site is kept at, in `UserDefaults`. A site at actual size has no entry.
public struct PageZoomStore {
    public static let key = "PageZoomBySite"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The level pages on `url`'s site are shown at. 1 when none was kept, and for addresses that aren't sites.
    public func zoom(for url: URL?) -> Double {
        guard let site = Self.site(for: url) else { return 1 }
        return (defaults.dictionary(forKey: Self.key)?[site] as? Double) ?? 1
    }

    /// Keeps `zoom` for `url`'s site. Actual size forgets the site.
    public func setZoom(_ zoom: Double, for url: URL?) {
        guard let site = Self.site(for: url) else { return }
        var levels = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        levels[site] = PageZoom.isActualSize(zoom) ? nil : zoom
        if levels.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(levels, forKey: Self.key)
        }
    }

    /// True when two addresses share a kept zoom level.
    public static func sameSite(_ a: URL?, _ b: URL?) -> Bool {
        guard let siteA = site(for: a), let siteB = site(for: b) else { return false }
        return siteA == siteB
    }

    /// What a zoom level is kept under: the site for web pages, as content blocking counts sites, and one
    /// shared entry for local files. Nil for blank tabs and anything else.
    static func site(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host(), !host.isEmpty else { return nil }
            return siteKey(forHost: host)
        case "file":
            return "file"
        default:
            return nil
        }
    }
}
