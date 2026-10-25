import Foundation

/// A notice from the maintainer, shown once as an alert or a quiet banner, then never again for its id.
public struct RemoteMessage: Equatable, Sendable {
    public enum Style: String, Sendable {
        case alert
        case banner
    }

    public let id: String
    public let text: String
    /// An https page that tells more.
    public let link: URL?
    public let style: Style
    /// The oldest Sela that shows it, or nil for any.
    public let minimumVersion: AppVersion?
    /// The newest Sela that shows it, or nil for any.
    public let maximumVersion: AppVersion?

    /// Nil when the text is empty or longer than 1000 characters.
    public init?(id: String, text: String, link: URL? = nil, style: Style = .banner, minimumVersion: AppVersion? = nil, maximumVersion: AppVersion? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1000 else { return nil }
        self.id = id
        self.text = text
        self.link = link
        self.style = style
        self.minimumVersion = minimumVersion
        self.maximumVersion = maximumVersion
    }

    /// Whether this Sela, at `version`, is one the message is for. A version Sela can't read only gets
    /// messages with no bounds.
    public func applies(to version: String) -> Bool {
        guard minimumVersion != nil || maximumVersion != nil else { return true }
        guard let version = AppVersion(version) else { return false }
        if let minimumVersion, version < minimumVersion { return false }
        if let maximumVersion, version > maximumVersion { return false }
        return true
    }

    static func parseLink(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}

/// A dotted version number such as 0.1.3. Missing parts count as 0, so 1.2 equals 1.2.0.
public struct AppVersion: Comparable, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let parts = pieces.compactMap { Int($0) }
        guard !pieces.isEmpty, pieces.count <= 4, parts.count == pieces.count, parts.allSatisfy({ $0 >= 0 }) else { return nil }
        self.parts = parts
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        let left = lhs.parts + Array(repeating: 0, count: count - lhs.parts.count)
        let right = rhs.parts + Array(repeating: 0, count: count - rhs.parts.count)
        return left.lexicographicallyPrecedes(right)
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The ids of messages already shown, stored in `UserDefaults`.
public struct RemoteMessageLedger {
    public static let key = "RemoteMessagesShown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The message to show now, if there is one this version hasn't shown.
    public func messageToShow(in settings: RemoteSettings, appVersion: String) -> RemoteMessage? {
        guard let message = settings.message, !shown.contains(message.id), message.applies(to: appVersion) else { return nil }
        return message
    }

    public func markShown(_ message: RemoteMessage) {
        defaults.set(shown + [message.id], forKey: Self.key)
    }

    private var shown: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}
