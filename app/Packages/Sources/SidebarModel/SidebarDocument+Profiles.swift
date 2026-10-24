import Foundation

extension SidebarDocument {
    public func profile(_ id: ProfileID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// The profile a space's tabs use. Default for a space that doesn't exist.
    public func profileID(of spaceID: SpaceID) -> ProfileID {
        space(spaceID)?.profileID ?? .default
    }

    /// The spaces that use a profile, in display order.
    public func spaces(using profileID: ProfileID) -> [Space] {
        spaces.filter { $0.profileID == profileID }
    }

    /// Adds a profile at the end. No space uses it yet.
    @discardableResult
    public mutating func addProfile(name: String, icon: String? = nil, color: RGBAColor? = nil) -> ProfileID {
        let id = ProfileID.make()
        profiles.append(Profile(id: id, name: name, icon: icon, color: color))
        return id
    }

    public mutating func updateProfile(_ id: ProfileID, name: String, icon: String?, color: RGBAColor?) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SidebarError.profileNotFound(id) }
        profiles[index].name = name
        profiles[index].icon = icon
        profiles[index].color = color
    }

    /// Removes a profile. Its spaces move to Default. Returns the spaces that moved.
    @discardableResult
    public mutating func removeProfile(_ id: ProfileID) throws -> [SpaceID] {
        guard id != .default else { throw SidebarError.cannotRemoveDefaultProfile }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SidebarError.profileNotFound(id) }
        profiles.remove(at: index)
        var moved: [SpaceID] = []
        for spaceIndex in spaces.indices where spaces[spaceIndex].profileID == id {
            spaces[spaceIndex].profileID = .default
            moved.append(spaces[spaceIndex].id)
        }
        return moved
    }

    public mutating func setProfile(_ profileID: ProfileID, of spaceID: SpaceID) throws {
        guard profile(profileID) != nil else { throw SidebarError.profileNotFound(profileID) }
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { throw SidebarError.spaceNotFound(spaceID) }
        spaces[index].profileID = profileID
    }

    /// Checks that Default comes first, IDs are unique and every space's profile exists.
    func validateProfiles() throws {
        guard profiles.first?.id == .default else { throw SidebarError.integrity("the Default profile isn't first") }
        guard Set(profiles.map(\.id)).count == profiles.count else { throw SidebarError.integrity("two profiles share an ID") }
        for space in spaces where profile(space.profileID) == nil {
            throw SidebarError.integrity("space \(space.id) uses missing profile \(space.profileID)")
        }
    }
}
