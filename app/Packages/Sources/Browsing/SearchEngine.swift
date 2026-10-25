import Foundation
import RemoteSettings

/// Where a search from the address bar or command bar goes.
public struct SearchEngine: Hashable, Sendable {
    /// Stored as the choice in Settings, and matched against the remote settings' engines.
    public let id: String
    public let name: String
    /// The search address, with `%s` where the query goes.
    public let template: String

    public init(id: String, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    public static let google = SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s")
    public static let duckDuckGo = SearchEngine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s")
    public static let bing = SearchEngine(id: "bing", name: "Bing", template: "https://www.bing.com/search?q=%s")
    public static let ecosia = SearchEngine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q=%s")
    public static let kagi = SearchEngine(id: "kagi", name: "Kagi", template: "https://kagi.com/search?q=%s")
    public static let braveSearch = SearchEngine(id: "brave", name: "Brave Search", template: "https://search.brave.com/search?q=%s")
    public static let startpage = SearchEngine(id: "startpage", name: "Startpage", template: "https://www.startpage.com/sp/search?query=%s")

    /// The engines Sela ships with, in the order Settings lists them.
    public static let builtIn: [SearchEngine] = [.google, .duckDuckGo, .bing, .ecosia, .kagi, .braveSearch, .startpage]

    /// The built-in engines with the remote settings' changes, then the engines they add.
    /// A built-in engine whose remote change goes away falls back to its built-in template.
    public static func available(remote: RemoteSettings = .current) -> [SearchEngine] {
        var engines = builtIn.map { engine in
            remote.searchEngines.first { $0.id == engine.id }.map(SearchEngine.init) ?? engine
        }
        for added in remote.searchEngines where !engines.contains(where: { $0.id == added.id }) {
            engines.append(SearchEngine(added))
        }
        return engines
    }

    init(_ remote: RemoteSearchEngine) {
        self.init(id: remote.id, name: remote.name, template: remote.template)
    }

    public func searchURL(for query: String) -> URL? {
        Browsing.searchURL(template: template, query: query)
    }

    /// Whether `url` is a search on this engine.
    public func isSearch(_ url: URL) -> Bool {
        let prefix = template.prefix { $0 != "%" }
        return url.absoluteString.hasPrefix(prefix)
    }
}

/// `template` with `%s` replaced by `query`, escaped so the query's own `&`, `=`, `+` and `#` stay in it.
public func searchURL(template: String, query: String) -> URL? {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=?#")
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
    return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
}

/// The chosen search engine, stored in `UserDefaults`. Someone who hasn't chosen gets the remote settings'
/// default engine, or Google. A chosen engine the remote settings no longer offer gives the default
/// until it comes back, and the choice stays stored.
public struct SearchEngineSettings {
    public static let key = "SearchEngine"
    static let defaultEngine = SearchEngine.google

    private let defaults: UserDefaults
    private let remote: RemoteSettings

    public init(defaults: UserDefaults = .standard, remote: RemoteSettings = .current) {
        self.defaults = defaults
        self.remote = remote
    }

    public var available: [SearchEngine] {
        SearchEngine.available(remote: remote)
    }

    /// Until you choose, picking the engine already in use stores nothing, so a later change to the default still reaches you.
    public var engine: SearchEngine {
        get {
            let engines = available
            if let chosen = defaults.string(forKey: Self.key), let engine = engines.first(where: { $0.id == chosen }) {
                return engine
            }
            return engines.first { $0.id == remote.defaults.searchEngine }
                ?? engines.first { $0.id == Self.defaultEngine.id }
                ?? Self.defaultEngine
        }
        nonmutating set {
            if defaults.string(forKey: Self.key) == nil, newValue.id == engine.id { return }
            defaults.set(newValue.id, forKey: Self.key)
        }
    }
}
