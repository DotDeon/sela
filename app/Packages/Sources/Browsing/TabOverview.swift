import BrowserEngine
import CoreGraphics
import Foundation
import SidebarModel

/// One tile in the tab overview.
public struct TabOverviewItem: Equatable, Sendable {
    public var id: ItemID
    public var title: String
    public var url: URL?
    public var isSelected: Bool
    /// False for tabs with no page loaded: asleep, or pinned and not opened since launch.
    public var isLive: Bool

    public init(id: ItemID, title: String, url: URL?, isSelected: Bool, isLive: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.isSelected = isSelected
        self.isLive = isLive
    }
}

extension BrowserWindowModel {
    /// The current space's tabs, in sidebar order: pinned tabs, those in folders included, then today's tabs.
    public var overviewItems: [TabOverviewItem] {
        let document = sidebar.document
        guard let space = document.space(selectedSpaceID) else { return [] }
        let ids = document.tabIDs(under: space.pinnedContainerID) + document.tabIDs(under: space.unpinnedContainerID)
        return ids.compactMap { id in
            guard let item = document.item(id), case .tab(let info) = item.kind else { return nil }
            let page = pageForDisplay(for: id)
            let custom = item.title.flatMap { $0.isEmpty ? nil : $0 }
            let saved = info.savedTitle.flatMap { $0.isEmpty ? nil : $0 }
            let title = custom ?? page?.title ?? saved ?? info.savedURL?.host() ?? "New Tab"
            return TabOverviewItem(id: id, title: title, url: page?.url ?? info.savedURL, isSelected: id == selectedItemID, isLive: liveTab(for: id) != nil)
        }
    }
}

/// The tiles whose title or address holds every word typed, in their order. An empty query keeps them all.
public func filterOverview(_ items: [TabOverviewItem], query: String) -> [TabOverviewItem] {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return items }
    return items.filter { item in
        var address = item.url?.absoluteString.lowercased() ?? ""
        for prefix in ["https://", "http://"] where address.hasPrefix(prefix) {
            address.removeFirst(prefix.count)
        }
        if address.hasPrefix("www.") { address.removeFirst(4) }
        let text = "\(item.title.lowercased()) \(address)"
        return words.allSatisfy { text.contains($0) }
    }
}

/// Where the overview's tiles go: as many columns as fit, each tile shaped like a small window.
public struct OverviewGrid: Equatable, Sendable {
    public enum Move: Sendable {
        case left, right, up, down
    }

    public var columns: Int
    public var tileSize: CGSize
    public var spacing: CGFloat
    public var inset: CGFloat
    /// Room under each picture for the tab's title.
    public static let titleHeight: CGFloat = 28

    /// A grid for `width` points. Tiles stay between `minimumTileWidth` and half again as wide, and never
    /// fewer than one a row.
    public init(width: CGFloat, count: Int, minimumTileWidth: CGFloat = 220, spacing: CGFloat = 20, inset: CGFloat = 32) {
        self.spacing = spacing
        self.inset = inset
        let available = max(width - inset * 2, minimumTileWidth)
        let fit = max(Int((available + spacing) / (minimumTileWidth + spacing)), 1)
        // A few tabs don't stretch across a wide window.
        columns = max(min(fit, max(count, 1)), 1)
        let tileWidth = min((available - spacing * CGFloat(columns - 1)) / CGFloat(columns), minimumTileWidth * 1.5)
        tileSize = CGSize(width: floor(tileWidth), height: floor(tileWidth * 0.625) + Self.titleHeight)
    }

    public func rows(for count: Int) -> Int {
        count == 0 ? 0 : (count + columns - 1) / columns
    }

    /// The total size of `count` tiles with the inset around them.
    public func contentSize(for count: Int) -> CGSize {
        let rows = CGFloat(rows(for: count))
        let width = CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing + inset * 2
        let height = rows * tileSize.height + max(rows - 1, 0) * spacing + inset * 2
        return CGSize(width: width, height: height)
    }

    /// A tile's frame, counting down from the top left, with the grid centred in `width`.
    public func frame(at index: Int, width: CGFloat) -> CGRect {
        let gridWidth = contentSize(for: columns).width - inset * 2
        let left = max((width - gridWidth) / 2, inset)
        let column = index % columns
        let row = index / columns
        return CGRect(x: left + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width, height: tileSize.height)
    }

    /// Where an arrow key moves the highlight from `index`. Left and right wrap between rows; up and down
    /// stay put at the top and bottom, and down onto a short last row lands on its last tile.
    public func index(after move: Move, from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let index = min(max(index, 0), count - 1)
        switch move {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .up: return index >= columns ? index - columns : index
        case .down:
            guard index / columns < rows(for: count) - 1 else { return index }
            return min(index + columns, count - 1)
        }
    }
}
