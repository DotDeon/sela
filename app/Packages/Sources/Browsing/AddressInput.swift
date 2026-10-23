import Foundation

/// Turns what someone typed in the address bar into a URL to load.
public enum AddressInput {
    static let searchURLPrefix = "https://www.google.com/search?q="

    /// Nil for blank input. Otherwise a website, a local address, or a search.
    public static func resolve(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        if ["http://", "https://", "file://"].contains(where: lowered.hasPrefix) || lowered.hasPrefix("about:") {
            return URL(string: text.replacingOccurrences(of: " ", with: "%20"))
        }
        if text.contains(where: \.isWhitespace) {
            return search(text)
        }
        if text.wholeMatch(of: localAddress()) != nil {
            return URL(string: "http://" + text)
        }
        if looksLikeDomain(text) {
            return URL(string: "https://" + text)
        }
        return search(text)
    }

    /// `localhost` or an IPv4 address, with an optional port and path.
    private static func localAddress() -> some RegexComponent {
        /(?i)(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?([\/?#].*)?/
    }

    private static func looksLikeDomain(_ text: String) -> Bool {
        let host = text.prefix { !"/?:#".contains($0) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last, last.count >= 2 else { return false }
        return last.allSatisfy { $0.isASCII && $0.isLetter }
    }

    private static func search(_ query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: searchURLPrefix + encoded)
    }
}
