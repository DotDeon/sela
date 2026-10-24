import BrowserEngine
import Foundation

/// The camera and microphone choices you've made, per site, stored in `UserDefaults` under `SitePermissions`
/// as `[site: ["camera": Bool, "microphone": Bool]]`.
public struct SitePermissions {
    static let key = "SitePermissions"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True or false once you've chosen, nil before. Camera and microphone together need a choice for each:
    /// any "no" is a no, and a missing choice means asking.
    public func decision(for media: MediaCapture, on origin: URL) -> Bool? {
        let choices = stored[site(origin)] ?? [:]
        let answers = Self.kinds(media).map { choices[$0] }
        if answers.contains(false) { return false }
        if answers.contains(nil) { return nil }
        return true
    }

    public func remember(_ allowed: Bool, for media: MediaCapture, on origin: URL) {
        var all = stored
        var choices = all[site(origin)] ?? [:]
        for kind in Self.kinds(media) { choices[kind] = allowed }
        all[site(origin)] = choices
        defaults.set(all, forKey: Self.key)
    }

    public func forget(siteOf origin: URL) {
        var all = stored
        all[site(origin)] = nil
        defaults.set(all, forKey: Self.key)
    }

    private var stored: [String: [String: Bool]] {
        defaults.dictionary(forKey: Self.key) as? [String: [String: Bool]] ?? [:]
    }

    private func site(_ origin: URL) -> String {
        siteKey(forHost: origin.host() ?? origin.absoluteString)
    }

    private static func kinds(_ media: MediaCapture) -> [String] {
        switch media {
        case .camera: ["camera"]
        case .microphone: ["microphone"]
        case .cameraAndMicrophone: ["camera", "microphone"]
        }
    }
}
