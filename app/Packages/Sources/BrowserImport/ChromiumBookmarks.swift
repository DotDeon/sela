import Foundation

/// Reads Chromium's `Bookmarks` JSON. The bookmarks bar comes first, item for item. "Other bookmarks" and
/// "Mobile bookmarks" follow as folders when they hold anything, so nothing is left behind.
public func parseChromiumBookmarks(_ data: Data) throws -> [ImportedBookmark] {
    let file: ChromiumBookmarksFile
    do {
        file = try JSONDecoder().decode(ChromiumBookmarksFile.self, from: data)
    } catch {
        throw BrowserImportError.malformed("bookmarks: \(error)")
    }
    var bookmarks = file.roots.bookmarkBar?.children?.compactMap(\.bookmark) ?? []
    for (root, fallback) in [(file.roots.other, "Other bookmarks"), (file.roots.synced, "Mobile bookmarks")] {
        let children = root?.children?.compactMap(\.bookmark) ?? []
        guard !children.isEmpty else { continue }
        let title = root?.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        bookmarks.append(.folder(title: title, children: children))
    }
    return bookmarks
}

private struct ChromiumBookmarksFile: Decodable {
    struct Roots: Decodable {
        let bookmarkBar: Node?
        let other: Node?
        let synced: Node?
        enum CodingKeys: String, CodingKey {
            case bookmarkBar = "bookmark_bar", other, synced
        }
    }
    let roots: Roots
}

private struct Node: Decodable {
    let type: String?
    let name: String?
    let url: String?
    let children: [Node]?

    /// Nil for unknown kinds and addresses that don't parse.
    var bookmark: ImportedBookmark? {
        switch type {
        case "url":
            guard let url = url.flatMap(URL.init(string:)) else { return nil }
            return .link(title: name.flatMap { $0.isEmpty ? nil : $0 }, url: url)
        case "folder":
            return .folder(title: name ?? "", children: children?.compactMap(\.bookmark) ?? [])
        default:
            return nil
        }
    }
}
