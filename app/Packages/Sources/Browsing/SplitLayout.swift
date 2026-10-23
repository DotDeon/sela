import SidebarModel

/// The split a window is showing: its panes in order, and how they're laid out.
public struct SplitLayout: Equatable, Sendable {
    public let id: ItemID
    public let paneIDs: [ItemID]
    public let orientation: SplitOrientation
    public let fractions: [Double]

    public init(id: ItemID, paneIDs: [ItemID], orientation: SplitOrientation, fractions: [Double]) {
        self.id = id
        self.paneIDs = paneIDs
        self.orientation = orientation
        self.fractions = fractions
    }
}
