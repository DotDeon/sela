import Foundation

/// Where a search from the address bar or command bar goes.
public enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckDuckGo = "duckduckgo"
    case bing
    case ecosia
    case kagi
    case braveSearch = "brave"
    case startpage

    public var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .kagi: "Kagi"
        case .braveSearch: "Brave Search"
        case .startpage: "Startpage"
        }
    }

    /// The search address, with `%s` where the query goes.
    public var template: String {
        switch self {
        case .google: "https://www.google.com/search?q=%s"
        case .duckDuckGo: "https://duckduckgo.com/?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .ecosia: "https://www.ecosia.org/search?q=%s"
        case .kagi: "https://kagi.com/search?q=%s"
        case .braveSearch: "https://search.brave.com/search?q=%s"
        case .startpage: "https://www.startpage.com/sp/search?query=%s"
        }
    }

    public func searchURL(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// Whether `url` is a search on this engine.
    public func isSearch(_ url: URL) -> Bool {
        let prefix = template.prefix { $0 != "%" }
        return url.absoluteString.hasPrefix(prefix)
    }
}

/// The chosen search engine, stored in `UserDefaults`.
public struct SearchEngineSettings {
    public static let key = "SearchEngine"
    static let defaultEngine = SearchEngine.google

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var engine: SearchEngine {
        get { defaults.string(forKey: Self.key).flatMap(SearchEngine.init(rawValue:)) ?? Self.defaultEngine }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
