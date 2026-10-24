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
    case spaceNotFound(SpaceID)
    case cannotRemoveLastSpace
    case profileNotFound(ProfileID)
    case cannotRemoveDefaultProfile
    case notATab(ItemID)
    case notAFolder(ItemID)
    /// Only tabs outside favourites can be in a split.
    case notAllowedInSplit(ItemID)
    /// The split already has four panes.
    case splitFull(ItemID)
}
