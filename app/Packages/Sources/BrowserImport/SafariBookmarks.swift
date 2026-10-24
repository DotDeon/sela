import Foundation

/// Reads Safari's `Bookmarks.plist`. The favourites bar (`BookmarksBar`) comes first, item for item, and the
/// bookmarks menu follows as a folder when it holds anything. History and the reading list are left out.
public func parseSafariBookmarks(_ data: Data) throws -> [ImportedBookmark] {
    guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw BrowserImportError.malformed("Safari's bookmarks aren't a property list")
    }
    let lists = (root["Children"] as? [[String: Any]]) ?? []
    func children(of title: String) -> [ImportedBookmark] {
        let list = lists.first { $0["Title"] as? String == title && $0["WebBookmarkType"] as? String == "WebBookmarkTypeList" }
        return ((list?["Children"] as? [[String: Any]]) ?? []).compactMap(bookmark)
    }

    var bookmarks = children(of: "BookmarksBar")
    let menu = children(of: "BookmarksMenu")
    if !menu.isEmpty {
        bookmarks.append(.folder(title: "Bookmarks menu", children: menu))
    }
    return bookmarks
}

/// Nil for proxies, such as History, and addresses that don't parse.
private func bookmark(_ node: [String: Any]) -> ImportedBookmark? {
    switch node["WebBookmarkType"] as? String {
    case "WebBookmarkTypeLeaf":
        guard let url = (node["URLString"] as? String).flatMap(URL.init(string:)) else { return nil }
        let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
        return .link(title: title.flatMap { $0.isEmpty ? nil : $0 }, url: url)
    case "WebBookmarkTypeList":
        let children = ((node["Children"] as? [[String: Any]]) ?? []).compactMap(bookmark)
        return .folder(title: node["Title"] as? String ?? "", children: children)
    default:
        return nil
    }
}
