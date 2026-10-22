import Foundation

public enum SidebarError: Error, Equatable, Sendable {
    case itemNotFound(ItemID)
    case duplicateItem(ItemID)
    case wouldCreateCycle(ItemID)
    case cannotMoveContainer(ItemID)
    case parentCannotHaveChildren(ItemID)
    case integrity(String)
    case unsupportedVersion(Int)
    case corruptFile(backupURL: URL)
}
