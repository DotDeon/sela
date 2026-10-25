import Foundation
import SidebarModel

/// Folds records from iCloud into the sidebar. Each record is compared with the tag this Mac holds for it and
/// the later one wins. Then the tree is repaired, since records from two Macs can disagree about who holds
/// whom, and anything that ends up without a home goes in a "Recovered from" folder rather than being dropped.
public enum SyncMerge {
    public struct Result: Sendable {
        public var document: SidebarDocument
        /// The incoming records that won, with their tags, so the ledger can remember them.
        public var applied: [RecordKey: SyncRecord]
        /// The incoming records this Mac's own newer records beat.
        public var ignored: [RecordKey]
        /// How many tabs, folders and splits the sidebar had in its synced sections before.
        public var localItems: Int
        /// How many of those the merge removes.
        public var removedItems: Int
        /// How many items were put in a "Recovered from" folder.
        public var recoveredItems: Int

        /// True when the merge would take away more than half the synced items, which is what an empty or
        /// broken iCloud state looks like. The person decides.
        public var removesMostItems: Bool { removedItems > 0 && removedItems * 2 > localItems }
    }

    /// `known` holds the tag this Mac has for each record, local edits included. `localDeviceName` names the
    /// folder for items whose origin isn't known.
    public static func merge(_ incoming: [SyncRecord], into local: SidebarDocument, known: [RecordKey: ChangeTag], localDeviceName: String, now: Date) -> Result {
        let localBodies = SidebarRecords.bodies(of: local)
        var bodies = localBodies
        var tags = known
        var applied: [RecordKey: SyncRecord] = [:]
        var ignored: [RecordKey] = []

        for record in incoming {
            if let mine = known[record.key], mine >= record.tag {
                ignored.append(record.key)
                continue
            }
            if let earlier = applied[record.key], earlier.tag >= record.tag { continue }
            applied[record.key] = record
            tags[record.key] = record.tag
            bodies[record.key] = record.body
        }

        var builder = Builder(local: local, bodies: bodies, tags: tags, localDeviceName: localDeviceName, now: now)
        builder.build()
        builder.repair()
        let document = builder.document()
        let removed = localBodies.keys.filter { key in
            if case .item(let id) = key, case .item(let body)? = localBodies[key], !body.isContainer {
                return document.item(id) == nil
            }
            return false
        }.count
        return Result(document: document, applied: applied, ignored: ignored,
                      localItems: SidebarRecords.itemCount(localBodies), removedItems: removed, recoveredItems: builder.recovered)
    }

    /// Puts a sidebar together from record bodies plus what this Mac keeps for itself, then fixes the tree.
    private struct Builder {
        let local: SidebarDocument
        let bodies: [RecordKey: SyncRecord.Body]
        let tags: [RecordKey: ChangeTag]
        let localDeviceName: String
        let now: Date

        var items: [ItemID: SidebarItem] = [:]
        var spaces: [Space] = []
        var profiles: [Profile] = []
        var favoritesID: ItemID { local.favoritesContainerID }
        var recovered = 0

        init(local: SidebarDocument, bodies: [RecordKey: SyncRecord.Body], tags: [RecordKey: ChangeTag], localDeviceName: String, now: Date) {
            self.local = local
            self.bodies = bodies
            self.tags = tags
            self.localDeviceName = localDeviceName
            self.now = now
        }

        mutating func build() {
            var profileBodies: [(ProfileID, SyncRecord.ProfileBody)] = []
            var spaceBodies: [(SpaceID, SyncRecord.SpaceBody)] = []
            for (key, body) in bodies {
                switch (key, body) {
                case (.profile(let id), .profile(let profile)): profileBodies.append((id, profile))
                case (.space(let id), .space(let space)): spaceBodies.append((id, space))
                case (.item(let id), .item(let item)): items[realID(id)] = self.item(realID(id), from: item)
                default: break
                }
            }
            profiles = profileBodies
                .sorted { ($0.1.order, $0.0.rawValue) < ($1.1.order, $1.0.rawValue) }
                .map { Profile(id: $0.0, name: $0.1.name, icon: $0.1.icon, color: $0.1.color) }
            spaces = spaceBodies
                .sorted { ($0.1.order, $0.0.rawValue) < ($1.1.order, $1.0.rawValue) }
                .map { id, body in
                    Space(id: id, title: body.title, icon: body.icon, theme: body.theme, pinnedContainerID: body.pinnedContainerID,
                          unpinnedContainerID: local.space(id)?.unpinnedContainerID ?? .make(), profileID: body.profileID)
                }
            // This Mac's unpinned sections come along as they are, those of a space another Mac removed
            // included, so their tabs end up recovered rather than gone. A tab that iCloud now knows as
            // pinned leaves the unpinned section, since the record is the newer word on it.
            for space in local.spaces {
                var queue = [space.unpinnedContainerID]
                while !queue.isEmpty {
                    let id = queue.removeFirst()
                    guard var item = local.item(id), items[id] == nil else { continue }
                    item.childIDs.removeAll { items[$0] != nil }
                    items[id] = item
                    queue.append(contentsOf: item.childIDs)
                }
            }
        }

        private func realID(_ id: ItemID) -> ItemID {
            id == SidebarRecords.favoritesAlias ? favoritesID : id
        }

        /// A record's item, keeping what this Mac already knew about it that doesn't sync.
        private func item(_ id: ItemID, from body: SyncRecord.ItemBody) -> SidebarItem {
            let mine = local.item(id)
            var kind = body.kind
            switch (kind, mine?.kind) {
            case (.tab(var info), .tab(let known)?):
                info.lastActiveAt = known.lastActiveAt
                kind = .tab(info)
            case (.folder(var info), .folder(let known)?):
                info.isExpanded = known.isExpanded
                kind = .folder(info)
            default:
                break
            }
            return SidebarItem(id: id, parentID: body.parentID.map(realID), childIDs: body.childIDs, title: body.title,
                               createdAt: body.createdAt, isUnread: mine?.isUnread ?? false, kind: kind)
        }

        // MARK: Repair

        mutating func repair() {
            if spaces.isEmpty {
                // Every space gone means someone's sidebar was replaced wholesale. Keep this Mac's spaces.
                spaces = local.spaces
                for space in local.spaces {
                    for id in [space.pinnedContainerID, space.unpinnedContainerID] where items[id] == nil { items[id] = local.item(id) }
                }
            }
            ensureContainers()
            settleParentClaims()
            var orphans = breakCycles()
            orphans += detachMisplacedItems()
            orphans += dissolveUnusedContainers()
            orphans += tidySplits()
            file(orphans)
        }

        /// Favourites and both sections of every space exist and are containers.
        private mutating func ensureContainers() {
            var roles: [(ItemID, ContainerRole)] = [(favoritesID, .favorites)]
            for space in spaces {
                roles.append((space.pinnedContainerID, .pinned(space.id)))
                roles.append((space.unpinnedContainerID, .unpinned(space.id)))
            }
            for (id, role) in roles {
                if var item = items[id] {
                    item.kind = .container(role)
                    item.parentID = nil
                    items[id] = item
                } else {
                    items[id] = SidebarItem(id: id, parentID: nil, childIDs: [], title: nil, createdAt: now, isUnread: false, kind: .container(role))
                }
            }
        }

        /// Two parents may both list a child when it moved on one Mac while the other edited the old folder.
        /// The child's own record says where it is; failing that, the parent written last keeps it.
        private mutating func settleParentClaims() {
            var claims: [ItemID: [ItemID]] = [:]
            for id in items.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                var seen: Set<ItemID> = []
                items[id]!.childIDs = items[id]!.childIDs.filter { child in
                    child != id && items[child]?.isContainerItem == false && seen.insert(child).inserted
                }
                for child in items[id]!.childIDs { claims[child, default: []].append(id) }
            }
            for (child, parents) in claims {
                let own = items[child]!.parentID
                let winner: ItemID
                if let own, let parent = items[own], parent.canHoldChildren {
                    winner = own
                } else {
                    winner = parents.max { tag(of: $0) < tag(of: $1) }!
                }
                for parent in parents where parent != winner {
                    items[parent]!.childIDs.removeAll { $0 == child }
                }
                items[child]!.parentID = winner
            }
        }

        private func tag(of id: ItemID) -> ChangeTag {
            tags[.item(SidebarRecords.alias(id, in: local))] ?? ChangeTag(date: .distantPast, deviceID: "", deviceName: localDeviceName)
        }

        /// Folders that ended up inside each other. The one with the smallest ID leaves the loop.
        private mutating func breakCycles() -> [ItemID] {
            var orphans: [ItemID] = []
            while true {
                var inCycle: Set<ItemID> = []
                for item in items.values where !item.isContainerItem {
                    var seen: Set<ItemID> = [item.id]
                    var current = item
                    while let parentID = current.parentID, let parent = items[parentID] {
                        if !seen.insert(parentID).inserted {
                            inCycle.insert(item.id)
                            break
                        }
                        current = parent
                    }
                }
                guard let loser = inCycle.min(by: { $0.rawValue < $1.rawValue }) else { return orphans }
                if let parentID = items[loser]!.parentID { items[parentID]?.childIDs.removeAll { $0 == loser } }
                items[loser]!.parentID = nil
                orphans.append(loser)
            }
        }

        /// Items with no parent, a missing parent, a parent that's a tab, or a place a rule forbids.
        private mutating func detachMisplacedItems() -> [ItemID] {
            var orphans: [ItemID] = []
            for id in items.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let item = items[id]!
                guard !item.isContainerItem else { continue }
                guard let parentID = item.parentID, let parent = items[parentID], parent.canHoldChildren else {
                    orphans.append(id)
                    continue
                }
                let isTab: Bool
                if case .tab = item.kind { isTab = true } else { isTab = false }
                if parentID == favoritesID, !isTab {
                    items[parentID]!.childIDs.removeAll { $0 == id }
                    orphans.append(id)
                    continue
                }
                if case .split = parent.kind, !isTab {
                    // Only tabs sit in a split. Anything else moves up beside the split.
                    items[parentID]!.childIDs.removeAll { $0 == id }
                    if let grandparentID = parent.parentID, items[grandparentID] != nil {
                        items[grandparentID]!.childIDs.append(id)
                        items[id]!.parentID = grandparentID
                    } else {
                        orphans.append(id)
                    }
                    continue
                }
                if !parent.childIDs.contains(id) { items[parentID]!.childIDs.append(id) }
            }
            for id in orphans { items[id]!.parentID = nil }
            return orphans
        }

        /// A container no space or the favourites use, such as the pinned section of a space whose record
        /// now names another container, gives up its items and goes.
        private mutating func dissolveUnusedContainers() -> [ItemID] {
            var used: Set<ItemID> = [favoritesID]
            for space in spaces { used.formUnion([space.pinnedContainerID, space.unpinnedContainerID]) }
            var orphans: [ItemID] = []
            for item in items.values where item.isContainerItem && !used.contains(item.id) {
                for child in item.childIDs { items[child]?.parentID = nil }
                orphans += item.childIDs
                items[item.id] = nil
            }
            return orphans.sorted { $0.rawValue < $1.rawValue }
        }

        /// A split keeps two to four tabs. With one left it gives way to that tab; with none it goes.
        private mutating func tidySplits() -> [ItemID] {
            var orphans: [ItemID] = []
            for id in items.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard var split = items[id], case .split(var info) = split.kind else { continue }
                split.childIDs = Array(split.childIDs.prefix(SidebarDocument.maximumSplitPanes))
                let extra = items[id]!.childIDs.dropFirst(SidebarDocument.maximumSplitPanes)
                for child in extra { items[child]?.parentID = nil }
                orphans += extra
                if split.childIDs.count >= 2 {
                    info.fractions = SplitInfo.even(split.childIDs.count)
                    split.kind = .split(info)
                    items[id] = split
                    continue
                }
                let parentID = split.parentID
                if let parentID, items[parentID] != nil, let index = items[parentID]!.childIDs.firstIndex(of: id) {
                    if let last = split.childIDs.first {
                        items[parentID]!.childIDs[index] = last
                        items[last]!.parentID = parentID
                    } else {
                        items[parentID]!.childIDs.remove(at: index)
                    }
                } else {
                    for child in split.childIDs { items[child]?.parentID = nil }
                    orphans += split.childIDs
                }
                items[id] = nil
            }
            return orphans
        }

        /// Puts orphans in a "Recovered from <Mac>" folder in the first space's pinned section, one folder per Mac.
        private mutating func file(_ orphans: [ItemID]) {
            let orphans = orphans.filter { items[$0] != nil }
            guard !orphans.isEmpty, let home = spaces.first?.pinnedContainerID else { return }
            for id in orphans {
                let name = tag(of: id).deviceName
                let title = "Recovered from \(name.isEmpty ? localDeviceName : name)"
                let folderID = items[home]!.childIDs.first { child in
                    guard let folder = items[child], case .folder = folder.kind else { return false }
                    return folder.title == title
                } ?? makeFolder(title, in: home)
                items[folderID]!.childIDs.append(id)
                items[id]!.parentID = folderID
                recovered += 1
            }
        }

        private mutating func makeFolder(_ title: String, in parentID: ItemID) -> ItemID {
            let id = ItemID.make()
            items[id] = SidebarItem(id: id, parentID: parentID, childIDs: [], title: title, createdAt: now, isUnread: false,
                                    kind: .folder(FolderInfo(icon: nil, isExpanded: true)))
            items[parentID]!.childIDs.append(id)
            return id
        }

        func document() -> SidebarDocument {
            SidebarDocument(version: SidebarDocument.currentVersion, spaces: spaces, favoritesContainerID: favoritesID,
                            items: Array(items.values), profiles: profiles)
        }
    }
}

extension SidebarItem {
    fileprivate var isContainerItem: Bool {
        if case .container = kind { return true }
        return false
    }

    fileprivate var canHoldChildren: Bool {
        if case .tab = kind { return false }
        return true
    }
}
