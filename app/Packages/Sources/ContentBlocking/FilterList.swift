import Foundation

/// An ad blocking filter list Brow downloads and keeps up to date.
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
    public static let easyPrivacy = FilterList(id: "easyprivacy", title: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!)

    /// Ads, then trackers.
    public static let defaults = [easyList, easyPrivacy]
}
