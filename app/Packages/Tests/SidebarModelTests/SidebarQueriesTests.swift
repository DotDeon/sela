import Foundation
import Testing
@testable import SidebarModel

@Test func containerRoleWalksUp() {
    let doc = fixtureDocument()
    #expect(doc.containerRole(of: "t3") == .pinned("S"))
    #expect(doc.containerRole(of: "t2") == .unpinned("S"))
    #expect(doc.containerRole(of: "f1") == .favorites)
    #expect(doc.containerRole(of: "P") == .pinned("S"))
    #expect(doc.containerRole(of: "nope") == nil)
}

@Test func spaceIDOfFavoriteIsNil() {
    let doc = fixtureDocument()
    #expect(doc.spaceID(containing: "f1") == nil)
    #expect(doc.spaceID(containing: "t3") == "S")
    #expect(doc.spaceID(containing: "U") == "S")
}

@Test func tabIDsAreDepthFirst() {
    let doc = fixtureDocument()
    #expect(doc.tabIDs(under: "P") == ["t3", "t1"])
    #expect(doc.tabIDs(under: "U") == ["t2"])
    #expect(doc.tabIDs(under: "t1") == ["t1"])
}

@Test func canMoveMatchesMove() {
    let doc = fixtureDocument()
    #expect(!doc.canMove("folder", to: "sub"))
    #expect(doc.canMove("t1", to: "U"))
    #expect(!doc.canMove("P", to: "U"))
    #expect(!doc.canMove("t1", to: "t2"))
    #expect(!doc.canMove("nope", to: "U"))
}

@Test func favoritesHoldOnlyTabs() {
    let doc = fixtureDocument()
    #expect(!doc.canMove("folder", to: "F"))
    #expect(doc.canMove("t1", to: "F"))
}

@Test func validateRequiresASpace() {
    let doc = SidebarDocument(version: 1, spaces: [], favoritesContainerID: "F", items: [fixtureItem("F", parent: nil, kind: .container(.favorites))])
    #expect {
        try doc.validate()
    } throws: { error in
        if case SidebarError.integrity = error { return true }
        return false
    }
}
