import AppKit
import SidebarModel

extension NSPasteboard.PasteboardType {
    /// A sidebar tab or folder being dragged. The value is the item's ID.
    public static let sidebarItem = NSPasteboard.PasteboardType("app.brow.sidebar-item")
}

@MainActor
func pasteboardItem(for id: ItemID) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setString(id.rawValue, forType: .sidebarItem)
    return item
}

/// The sidebar item being dragged, if the drag holds one.
@MainActor
func draggedItemID(_ info: any NSDraggingInfo) -> ItemID? {
    info.draggingPasteboard.string(forType: .sidebarItem).map(ItemID.init(rawValue:))
}

/// A web address being dragged in from a page or another app.
@MainActor
func draggedURL(_ info: any NSDraggingInfo) -> URL? {
    guard let url = NSURL(from: info.draggingPasteboard) as URL?,
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme)
    else { return nil }
    return url
}
