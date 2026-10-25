import Foundation
import SidebarModel

/// Names one synced record: a space, an item in the pinned sections or favourites, or a profile.
/// Today's tabs, the archive and history never get a key, so they stay on the Mac they belong to.
public enum RecordKey: Hashable, Codable, Sendable, CustomStringConvertible {
    case space(SpaceID)
    case item(ItemID)
    case profile(ProfileID)

    /// The CloudKit record name. The prefix tells the kinds apart; the rest is the sidebar's own ID.
    public var recordName: String {
        switch self {
        case .space(let id): "space:\(id.rawValue)"
        case .item(let id): "item:\(id.rawValue)"
        case .profile(let id): "profile:\(id.rawValue)"
        }
    }

    public init?(recordName: String) {
        guard let colon = recordName.firstIndex(of: ":") else { return nil }
        let rest = String(recordName[recordName.index(after: colon)...])
        guard !rest.isEmpty else { return nil }
        switch recordName[..<colon] {
        case "space": self = .space(SpaceID(rawValue: rest))
        case "item": self = .item(ItemID(rawValue: rest))
        case "profile": self = .profile(ProfileID(rawValue: rest))
        default: return nil
        }
    }

    public var description: String { recordName }
}

/// When a record last changed and which Mac changed it. The later tag wins; the device ID breaks ties, so
/// every Mac picks the same winner.
public struct ChangeTag: Hashable, Codable, Sendable, Comparable {
    public var date: Date
    public var deviceID: String
    /// The Mac's name as it was then, for the "Recovered from" folder.
    public var deviceName: String

    public init(date: Date, deviceID: String, deviceName: String) {
        self.date = date
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    public static func < (lhs: ChangeTag, rhs: ChangeTag) -> Bool {
        (lhs.date, lhs.deviceID) < (rhs.date, rhs.deviceID)
    }
}

/// One record as it travels: its key, its change tag, and its body, or no body for a tombstone.
/// A deleted record stays in iCloud as a tombstone, so a Mac that comes back after a while learns of the deletion
/// and a later edit to the same record on another Mac can still win.
public struct SyncRecord: Equatable, Codable, Sendable {
    public var key: RecordKey
    public var tag: ChangeTag
    public var body: Body?

    public init(key: RecordKey, tag: ChangeTag, body: Body?) {
        self.key = key
        self.tag = tag
        self.body = body
    }

    public var isTombstone: Bool { body == nil }

    public enum Body: Equatable, Codable, Sendable {
        case space(SpaceBody)
        case item(ItemBody)
        case profile(ProfileBody)
    }

    /// A space without its unpinned section, which every Mac keeps for itself.
    public struct SpaceBody: Equatable, Codable, Sendable {
        public var title: String?
        public var icon: String?
        public var theme: SpaceTheme?
        public var pinnedContainerID: ItemID
        public var profileID: ProfileID
        /// Its place among the spaces. Ties go by ID.
        public var order: Int

        public init(title: String?, icon: String?, theme: SpaceTheme?, pinnedContainerID: ItemID, profileID: ProfileID, order: Int) {
            self.title = title
            self.icon = icon
            self.theme = theme
            self.pinnedContainerID = pinnedContainerID
            self.profileID = profileID
            self.order = order
        }
    }

    /// An item without the parts that belong to one Mac: when its tab was last active, whether it's unread,
    /// and whether its folder is open. The favourites container travels under the name `favorites`, since each
    /// Mac gave its own container a different ID.
    public struct ItemBody: Equatable, Codable, Sendable {
        public var parentID: ItemID?
        public var childIDs: [ItemID]
        public var title: String?
        public var createdAt: Date
        public var kind: SidebarItem.Kind

        public init(parentID: ItemID?, childIDs: [ItemID], title: String?, createdAt: Date, kind: SidebarItem.Kind) {
            self.parentID = parentID
            self.childIDs = childIDs
            self.title = title
            self.createdAt = createdAt
            self.kind = kind
        }
    }

    public struct ProfileBody: Equatable, Codable, Sendable {
        public var name: String
        public var icon: String?
        public var color: RGBAColor?
        public var order: Int

        public init(name: String, icon: String?, color: RGBAColor?, order: Int) {
            self.name = name
            self.icon = icon
            self.color = color
            self.order = order
        }
    }
}
