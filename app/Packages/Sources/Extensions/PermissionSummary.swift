import Foundation

/// Plain sentences for what an extension asks to do, for the questions Sela asks before allowing it.
public enum PermissionSummary {
    /// One line per kind of access, the broadest first. Empty when nothing needs the user's say.
    public static func lines(permissions: Set<String>, matchPatterns: Set<String>) -> [String] {
        var lines: [String] = []
        if let sites = sitesLine(matchPatterns) { lines.append(sites) }
        if permissions.contains("activeTab") {
            lines.append("Read and change the page you're on when you use it")
        }
        if !permissions.isDisjoint(with: ["tabs", "webNavigation"]) {
            lines.append("See the address and title of every tab")
        }
        if permissions.contains("cookies") {
            lines.append("Read and change cookies")
        }
        if !permissions.isDisjoint(with: ["declarativeNetRequest", "declarativeNetRequestWithHostAccess", "webRequest"]) {
            lines.append("Block or change what pages load")
        }
        if permissions.contains("clipboardWrite") {
            lines.append("Copy text to your clipboard")
        }
        if permissions.contains("nativeMessaging") {
            lines.append("Talk to apps on your Mac, which Sela doesn't support yet")
        }
        return lines
    }

    /// The hosts the patterns cover, such as `example.com`, or nil when they cover every site.
    public static func hosts(in matchPatterns: Set<String>) -> [String]? {
        var hosts: Set<String> = []
        for pattern in matchPatterns {
            if pattern == "<all_urls>" { return nil }
            guard let range = pattern.range(of: "://") else { continue }
            let host = pattern[range.upperBound...].prefix { $0 != "/" }
            if host == "*" { return nil }
            let trimmed = host.hasPrefix("*.") ? host.dropFirst(2) : host[...]
            if !trimmed.isEmpty { hosts.insert(String(trimmed)) }
        }
        return hosts.sorted()
    }

    private static func sitesLine(_ matchPatterns: Set<String>) -> String? {
        guard !matchPatterns.isEmpty else { return nil }
        guard let hosts = hosts(in: matchPatterns) else { return "Read and change everything on every website" }
        switch hosts.count {
        case 0: return nil
        case 1: return "Read and change your data on \(hosts[0])"
        case 2: return "Read and change your data on \(hosts[0]) and \(hosts[1])"
        default:
            let others = hosts.count - 2
            return "Read and change your data on \(hosts[0]), \(hosts[1]) and \(others) other \(others == 1 ? "site" : "sites")"
        }
    }
}
