import Foundation

/// Safari's version, used when the installed Safari can't be read.
private let fallbackSafariVersion = "27.0"

/// The text WebKit appends to its user agent so sites treat Brow like Safari.
/// WebKit's default user agent has no `Safari/` token, and Google and others serve worse pages or block sign-in without it.
func safariApplicationName(infoPlistURL: URL) -> String {
    let info = (try? Data(contentsOf: infoPlistURL))
        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let version = info?["CFBundleShortVersionString"] as? String ?? fallbackSafariVersion
    return "Version/\(version) Safari/605.1.15"
}
