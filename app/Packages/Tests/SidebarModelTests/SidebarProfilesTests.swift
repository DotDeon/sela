import Foundation
import Testing
@testable import SidebarModel

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "sela-profiles-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func everyDocumentHasTheDefaultProfileFirst() throws {
    let doc = fixtureDocument()
    #expect(doc.profiles.map(\.id) == [.default])
    #expect(doc.profiles.first?.name == "Default")
    #expect(doc.space("S")?.profileID == .default)

    let reordered = SidebarDocument(version: 2, spaces: doc.spaces, favoritesContainerID: "F", items: doc.allItems,
                                    profiles: [Profile(id: "work", name: "Work"), Profile(id: .default, name: "Home")])
    #expect(reordered.profiles.map(\.id) == [.default, "work"])
    #expect(reordered.profiles.first?.name == "Home")
}

@Test func spacesWithAMissingProfileUseDefault() {
    let doc = fixtureDocument()
    var space = doc.spaces[0]
    space.profileID = "gone"
    let fixed = SidebarDocument(version: 2, spaces: [space], favoritesContainerID: "F", items: doc.allItems)
    #expect(fixed.space("S")?.profileID == .default)
}

@Test func addAndAssignProfile() throws {
    var doc = fixtureDocument()
    let work = doc.addProfile(name: "Work")
    #expect(doc.profiles.map(\.name) == ["Default", "Work"])
    #expect(UUID(uuidString: work.rawValue) != nil)
    try doc.setProfile(work, of: "S")
    #expect(doc.profileID(of: "S") == work)
    #expect(doc.spaces(using: work).map(\.id) == ["S"])
    try doc.validate()
}

@Test func assigningAnUnknownProfileThrows() {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.profileNotFound("nope")) {
        try doc.setProfile("nope", of: "S")
    }
}

@Test func removingAProfileMovesItsSpacesToDefault() throws {
    var doc = fixtureDocument()
    let work = doc.addProfile(name: "Work")
    let other = doc.addSpace(title: "Other", icon: nil, now: fixtureDate)
    try doc.setProfile(work, of: "S")
    try doc.setProfile(work, of: other)
    let moved = try doc.removeProfile(work)
    #expect(moved == ["S", other])
    #expect(doc.profiles.map(\.id) == [.default])
    #expect(doc.spaces.allSatisfy { $0.profileID == .default })
    try doc.validate()
}

@Test func theDefaultProfileCantBeRemoved() {
    var doc = fixtureDocument()
    #expect(throws: SidebarError.cannotRemoveDefaultProfile) {
        try doc.removeProfile(.default)
    }
}

@Test func updateProfileChangesNameIconAndColour() throws {
    var doc = fixtureDocument()
    let id = doc.addProfile(name: "Work")
    let colour = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    try doc.updateProfile(id, name: "Job", icon: "💼", color: colour)
    #expect(doc.profile(id) == Profile(id: id, name: "Job", icon: "💼", color: colour))
}

@Test func validateRejectsASpaceWithAMissingProfile() {
    var doc = fixtureDocument()
    doc.spaces[0].profileID = "gone"
    #expect(throws: SidebarError.self) { try doc.validate() }
}

@Test func profilesRoundTripThroughTheFile() throws {
    let url = try makeTempDirectory().appending(path: "Sidebar.json")
    var doc = fixtureDocument()
    let work = doc.addProfile(name: "Work", icon: "💼")
    try doc.setProfile(work, of: "S")
    let store = SidebarDocumentStore(fileURL: url)
    try store.save(doc)
    let loaded = try #require(try store.load())
    #expect(loaded == doc)
    #expect(loaded.profileID(of: "S") == work)
}

/// A sidebar saved before profiles existed has no `profiles` and no `profileID` on its spaces.
@Test func sidebarsFromBeforeProfilesLoadWithDefault() throws {
    let url = try makeTempDirectory().appending(path: "Sidebar.json")
    let store = SidebarDocumentStore(fileURL: url)
    let doc = fixtureDocument()
    try store.save(doc)
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    json["profiles"] = nil
    json["spaces"] = (json["spaces"] as? [[String: Any]])?.map { space in
        var space = space
        space["profileID"] = nil
        return space
    }
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    #expect(try !String(contentsOf: url, encoding: .utf8).contains("profile"))

    let loaded = try #require(try store.load())
    #expect(loaded == doc)
    #expect(loaded.profiles == [Profile(id: .default, name: "Default")])
    #expect(loaded.space("S")?.profileID == .default)
}
