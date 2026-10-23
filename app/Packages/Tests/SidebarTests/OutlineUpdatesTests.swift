import Foundation
import Testing
import Sidebar

@Test func updatesForInsertAndRemove() {
    let old: OutlineSnapshot = [nil: [.item("a"), .item("b"), .item("c")]]
    let new: OutlineSnapshot = [nil: [.item("a"), .item("c"), .item("d")]]
    #expect(outlineUpdates(from: old, to: new) == [.remove(parent: nil, index: 1), .insert(parent: nil, index: 2)])
}

@Test func removalsComeFirstInDescendingOrder() {
    let old: OutlineSnapshot = [nil: [.item("a"), .item("b"), .item("c"), .item("d")]]
    let new: OutlineSnapshot = [nil: [.item("x"), .item("b"), .item("d")]]
    #expect(outlineUpdates(from: old, to: new) == [
        .remove(parent: nil, index: 2),
        .remove(parent: nil, index: 0),
        .insert(parent: nil, index: 0),
    ])
}

@Test func moveBetweenParentsIsRemoveThenInsert() {
    let old: OutlineSnapshot = [nil: [.item("a"), .item("f")], .item("f"): []]
    let new: OutlineSnapshot = [nil: [.item("f")], .item("f"): [.item("a")]]
    #expect(outlineUpdates(from: old, to: new) == [.remove(parent: nil, index: 0), .insert(parent: .item("f"), index: 0)])
}

@Test func newlyExpandedFolderNeedsNoChildUpdates() {
    let old: OutlineSnapshot = [nil: [.item("f")]]
    let new: OutlineSnapshot = [nil: [.item("f")], .item("f"): [.item("a")]]
    #expect(outlineUpdates(from: old, to: new) == [])
}

@Test func unchangedSnapshotNeedsNothing() {
    let snapshot: OutlineSnapshot = [nil: [.item("a"), .divider, .item("b")]]
    #expect(outlineUpdates(from: snapshot, to: snapshot) == [])
}
