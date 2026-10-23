import Foundation

/// The part of a host that names the site, so links between a site's own subdomains count as the same site:
/// `mail.google.com` is `google.com`, and `online.fnb.co.za` is `fnb.co.za`. Hosts like `co.za` keep three labels.
/// IP addresses and single-word hosts such as `localhost` stay as they are.
public func siteKey(forHost host: String) -> String {
    let host = host.lowercased()
    let labels = host.split(separator: ".")
    let isIPAddress = labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
    guard labels.count > 2, !isIPAddress else { return host }
    let last = labels[labels.count - 1]
    let secondLast = labels[labels.count - 2]
    let keep = last.count == 2 && secondLast.count <= 3 ? 3 : 2
    return labels.suffix(keep).joined(separator: ".")
}
