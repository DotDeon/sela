import Foundation
import PublicSuffixList

/// The part of a host that names the site, so links between a site's own subdomains count as the same site:
/// `mail.google.com` is `google.com`, and `online.fnb.co.za` is `fnb.co.za`. Uses the public suffix list.
/// IP addresses and single-word hosts such as `localhost` stay as they are.
public func siteKey(forHost host: String) -> String {
    let host = host.lowercased()
    // Addresses aren't domains, so the suffix list would cut them up.
    if host.contains(":") || host.split(separator: ".").allSatisfy({ Int($0) != nil }) { return host }
    return PublicSuffixList.effectiveTLDPlusOne(host) ?? host
}
