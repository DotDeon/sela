import Foundation

// Decodable mirror of the parts of Arc's StorableSidebar.json that Sela imports.
// Unknown keys are ignored. All timestamps are seconds since 1 January 2001.

struct ArcStorableSidebar: Decodable {
    struct Sidebar: Decodable {
        var containers: [ArcSidebarContainer]
    }

    var sidebar: Sidebar
}

struct ArcSidebarContainer: Decodable {
    var spaces: AlternatingPairs<String, ArcSpace>?
    var items: AlternatingPairs<String, LossyArcItem>?
    var topAppsContainerIDs: AlternatingPairs<ArcProfileReference, String>?
}

/// `{"default": true}` for the default profile. Other profile shapes decode with `isDefault == false`.
struct ArcProfileReference: Decodable {
    var isDefault: Bool

    private enum CodingKeys: String, CodingKey { case `default` }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .default) ?? false
    }
}

struct ArcCustomInfo: Decodable {
    struct IconType: Decodable {
        var icon: String?
    }

    var iconType: IconType?
}

struct ArcSpace: Decodable {
    var id: String
    var title: String?
    var customInfo: ArcCustomInfo?
    /// Alternating label and container ID, like `["pinned", "<id>", "unpinned", "<id>"]`.
    var containerIDs: [String]?

    func containerID(labelled label: String) -> String? {
        guard let ids = containerIDs else { return nil }
        var index = 0
        while index + 1 < ids.count {
            if ids[index] == label { return ids[index + 1] }
            index += 2
        }
        return nil
    }
}

struct ArcItem: Decodable {
    var id: String
    var parentID: String?
    var childrenIds: [String]?
    var title: String?
    var createdAt: Double?
    var isUnread: Bool?
    var data: ArcItemData
}

/// An item that failed to decode doesn't fail the whole file. The pair key still identifies it.
enum LossyArcItem: Decodable {
    case readable(ArcItem)
    case unreadable

    init(from decoder: Decoder) throws {
        if let item = try? ArcItem(from: decoder) {
            self = .readable(item)
        } else {
            self = .unreadable
        }
    }
}

struct ArcTab: Decodable {
    var savedURL: String?
    var savedTitle: String?
    var timeLastActiveAt: Double?
    var savedMuteStatus: String?
}

struct ArcList: Decodable {
    var customInfo: ArcCustomInfo?
}

enum ArcContainerType: Decodable {
    case spaceItems
    case topApps
    case other(String)

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        switch container.allKeys.first?.stringValue {
        case "spaceItems": self = .spaceItems
        case "topApps": self = .topApps
        case let other: self = .other(other ?? "")
        }
    }
}

struct ArcItemContainer: Decodable {
    var containerType: ArcContainerType
}

/// The single-key `data` payload of an item. Unknown kinds keep their key name.
enum ArcItemData: Decodable {
    case tab(ArcTab)
    case list(ArcList)
    case itemContainer(ArcItemContainer)
    case unsupported(String)

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let key = container.allKeys.first else {
            self = .unsupported("")
            return
        }
        switch key.stringValue {
        case "tab": self = .tab(try container.decode(ArcTab.self, forKey: key))
        case "list": self = .list(try container.decode(ArcList.self, forKey: key))
        case "itemContainer": self = .itemContainer(try container.decode(ArcItemContainer.self, forKey: key))
        default: self = .unsupported(key.stringValue)
        }
    }

    var kindName: String {
        switch self {
        case .tab: "tab"
        case .list: "list"
        case .itemContainer: "itemContainer"
        case .unsupported(let name): name
        }
    }
}
