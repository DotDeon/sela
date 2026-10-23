import Foundation

/// One step of an animated outline update, in the order `NSOutlineView` needs them.
public enum OutlineUpdate: Equatable, Sendable {
    case remove(parent: OutlineRow?, index: Int)
    case insert(parent: OutlineRow?, index: Int)
}

/// The removals and insertions that turn `old` into `new`. Only parents visible in both are compared;
/// a parent that just appeared brings its children with it. Removals come first, highest index first
/// within each parent, then insertions, lowest index first. A moved row is a removal and an insertion.
public func outlineUpdates(from old: OutlineSnapshot, to new: OutlineSnapshot) -> [OutlineUpdate] {
    var removals: [OutlineUpdate] = []
    var insertions: [OutlineUpdate] = []
    let parents = new.keys.filter { old[$0] != nil }.sorted { describe($0) < describe($1) }
    for parent in parents {
        let difference = new[parent]!.difference(from: old[parent]!)
        removals += difference.removals.map(\.offset).sorted(by: >).map { .remove(parent: parent, index: $0) }
        insertions += difference.insertions.map(\.offset).sorted().map { .insert(parent: parent, index: $0) }
    }
    return removals + insertions
}

/// A stable sort key, so the update order doesn't depend on dictionary order.
private func describe(_ parent: OutlineRow?) -> String {
    switch parent {
    case nil: ""
    case .divider: "divider"
    case .item(let id): "item:\(id.rawValue)"
    }
}

private extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case .insert(let offset, _, _), .remove(let offset, _, _): offset
        }
    }
}
