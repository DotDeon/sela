import Foundation

/// Identifies a sidebar item. Imported Arc items keep their Arc IDs.
public struct ItemID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func make() -> ItemID { ItemID(rawValue: UUID().uuidString) }
    public var description: String { rawValue }
}

/// Identifies a space. Imported Arc spaces keep their Arc IDs.
public struct SpaceID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func make() -> SpaceID { SpaceID(rawValue: UUID().uuidString) }
    public var description: String { rawValue }
}

/// Identifies a profile. New profiles get a UUID, which also names their website data on disk.
public struct ProfileID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The profile every sidebar has. It uses the website data Sela kept before profiles existed.
    public static let `default`: ProfileID = "default"

    public static func make() -> ProfileID { ProfileID(rawValue: UUID().uuidString) }
    public var description: String { rawValue }
}
