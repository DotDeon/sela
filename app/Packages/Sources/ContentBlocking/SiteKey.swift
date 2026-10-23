import Foundation
import PublicSuffixList

/// The site a page belongs to for ad blocking settings: its registrable domain, such as `bbc.co.uk` for
/// `news.bbc.co.uk`, or the whole host when there's none, such as `localhost`. Nil for addresses with no host.
public func contentBlockingSite(for url: URL) -> String? {
    guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
    // Addresses aren't domains, so the suffix list would cut them up.
    if host.contains(":") || host.split(separator: ".").allSatisfy({ Int($0) != nil }) { return host }
    return PublicSuffixList.effectiveTLDPlusOne(host) ?? host
}
