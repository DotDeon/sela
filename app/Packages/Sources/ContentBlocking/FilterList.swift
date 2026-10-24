import Foundation

/// An ad blocking filter list Sela downloads and keeps up to date.
public struct FilterList: Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL

    public init(id: String, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }

    public static let easyList = FilterList(id: "easylist", title: "EasyList", url: URL(string: "https://easylist.to/easylist/easylist.txt")!)
    /// EasyList plus AdGuard's own rules, built for Safari. Includes the scriptlets that remove YouTube's video ads.
    public static let adGuardBase = FilterList(id: "adguard-base", title: "AdGuard Base", url: URL(string: "https://filters.adtidy.org/extension/safari/filters/2.txt")!)
    public static let easyPrivacy = FilterList(id: "easyprivacy", title: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!)

    /// Ads, then trackers.
    public static let defaults = [adGuardBase, easyPrivacy]
}
