import Foundation
import Synchronization

/// Behaviour the maintainer can change without a release, read from `remote-settings.json` on Sela's website.
/// It holds data only. Every part is optional, and a part with the wrong type or a value that fails its checks
/// is left out on its own, so one mistake doesn't throw away the rest of the file.
public struct RemoteSettings: Equatable, Sendable {
    /// The only `version` this Sela reads. Keys it doesn't know are ignored, so new ones can be added without
    /// changing the version. Change it only when an existing key changes meaning.
    public static let version = 1

    /// Changes to the built-in search engines, matched by id, and new ones.
    public var searchEngines: [RemoteSearchEngine] = []
    /// Values for settings people haven't changed themselves.
    public var defaults = RemoteDefaults()
    /// On and off switches by name. See `FeatureFlags`.
    public var features: [String: Bool] = [:]
    public var message: RemoteMessage?

    public static let empty = RemoteSettings()

    public init(searchEngines: [RemoteSearchEngine] = [], defaults: RemoteDefaults = RemoteDefaults(), features: [String: Bool] = [:], message: RemoteMessage? = nil) {
        self.searchEngines = searchEngines
        self.defaults = defaults
        self.features = features
        self.message = message
    }

    /// Nil when `data` isn't a JSON object with `"version": 1`.
    public init?(json data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == Self.version else { return nil }
        self = file.settings
    }

    /// The settings Sela uses now. The app sets them once the file is checked, and settings read them.
    public static var current: RemoteSettings {
        get { shared.withLock { $0 } }
        set { shared.withLock { $0 = newValue } }
    }

    private static let shared = Mutex(RemoteSettings.empty)
}

/// A search engine from the remote settings. The template is an https address with `%s` where the query goes.
public struct RemoteSearchEngine: Equatable, Sendable {
    public let id: String
    public let name: String
    public let template: String

    /// Nil when the id, name or template fails its checks.
    public init?(id: String, name: String, template: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteSettings.isValidID(id), !name.isEmpty, name.count <= 40, Self.isValidTemplate(template) else { return nil }
        self.id = id
        self.name = name
        self.template = template
    }

    static func isValidTemplate(_ template: String) -> Bool {
        guard template.count <= 500, template.contains("%s"),
              let url = URL(string: template.replacingOccurrences(of: "%s", with: "q")),
              url.scheme == "https", let host = url.host(), !host.isEmpty
        else { return false }
        return true
    }
}

/// Defaults for settings people haven't changed. Each setting checks the value again before using it.
public struct RemoteDefaults: Equatable, Sendable {
    /// The id of the search engine for people who haven't picked one.
    public var searchEngine: String?
    public var tabSleepMinutes: Int?
    public var autoPictureInPicture: Bool?

    public init(searchEngine: String? = nil, tabSleepMinutes: Int? = nil, autoPictureInPicture: Bool? = nil) {
        self.searchEngine = searchEngine
        self.tabSleepMinutes = tabSleepMinutes
        self.autoPictureInPicture = autoPictureInPicture
    }
}

extension RemoteSettings {
    /// Lowercase letters, digits and hyphens, up to 64 characters.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}

// MARK: Decoding

/// Decodes a value, or nil when it's there but has the wrong shape, so one bad entry doesn't fail its neighbours.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

private struct File: Decodable {
    let version: Int?
    let settings: RemoteSettings

    enum Keys: String, CodingKey {
        case version, searchEngines, defaults, features, message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        version = container.lenient(Int.self, .version)
        let engines = container.lenient([Lenient<EngineEntry>].self, .searchEngines) ?? []
        let features = container.lenient([String: Lenient<Bool>].self, .features) ?? [:]
        settings = RemoteSettings(
            searchEngines: engines.compactMap { $0.value?.engine },
            defaults: container.lenient(DefaultsEntry.self, .defaults)?.defaults ?? RemoteDefaults(),
            features: features.compactMapValues(\.value),
            message: container.lenient(MessageEntry.self, .message)?.message
        )
    }
}

private struct EngineEntry: Decodable {
    let engine: RemoteSearchEngine?

    enum Keys: String, CodingKey { case id, name, template }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let id = container.lenient(String.self, .id), let name = container.lenient(String.self, .name),
              let template = container.lenient(String.self, .template)
        else {
            engine = nil
            return
        }
        engine = RemoteSearchEngine(id: id, name: name, template: template)
    }
}

private struct DefaultsEntry: Decodable {
    let defaults: RemoteDefaults

    enum Keys: String, CodingKey { case searchEngine, tabSleepMinutes, autoPictureInPicture }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        defaults = RemoteDefaults(
            searchEngine: container.lenient(String.self, .searchEngine).flatMap { RemoteSettings.isValidID($0) ? $0 : nil },
            tabSleepMinutes: container.lenient(Int.self, .tabSleepMinutes).flatMap { $0 >= 0 ? $0 : nil },
            autoPictureInPicture: container.lenient(Bool.self, .autoPictureInPicture)
        )
    }
}

private struct MessageEntry: Decodable {
    let message: RemoteMessage?

    enum Keys: String, CodingKey { case id, text, link, style, minimumVersion, maximumVersion }

    /// A link or version bound that's there but unreadable drops the whole message, rather than showing it
    /// to the wrong people or without its link.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        func optional<T>(_ key: Keys, _ parse: (String) -> T?) -> T?? {
            guard container.contains(key) else { return .some(nil) }
            guard let text = container.lenient(String.self, key), let value = parse(text) else { return nil }
            return .some(value)
        }
        guard let id = container.lenient(String.self, .id), RemoteSettings.isValidID(id),
              let text = container.lenient(String.self, .text),
              let link = optional(.link, RemoteMessage.parseLink),
              let minimum = optional(.minimumVersion, AppVersion.init),
              let maximum = optional(.maximumVersion, AppVersion.init)
        else {
            message = nil
            return
        }
        let style = container.lenient(String.self, .style).flatMap(RemoteMessage.Style.init(rawValue:)) ?? .banner
        message = RemoteMessage(id: id, text: text, link: link, style: style, minimumVersion: minimum, maximumVersion: maximum)
    }
}
