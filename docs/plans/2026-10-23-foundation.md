# Foundation implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** A Swift package holding Brow's sidebar data model and storage, an importer that turns Arc's `StorableSidebar.json` into that model, and a `brow-arc` command-line tool that snapshots Arc's data and checks an import.

**Architecture:** One Swift package at `app/Packages` with a library target per module. `SidebarModel` owns the types, tree operations and JSON storage. `ArcImport` depends on it and reads Arc's file. `ArcSnapshot` copies Arc's data folder. The `brow-arc` executable wires the last two to the command line. No UI and no browser engine in this plan. Those come in the next plan.

**Tech stack:** Swift 6 language mode, Swift Package Manager, Swift Testing (`import Testing`), Foundation and AppKit (only for `NSRunningApplication` in the CLI). No third-party dependencies.

**Spec:** `docs/design/2026-10-23-brow-design.md`

**Next plans:** engine protocols and a WebKit browser window, then the sidebar UI, then archiving, command bar, split view, Peek and sync.

## Global constraints

- Mac only. Package platform floor `.macOS(.v15)`. `// swift-tools-version: 6.0`.
- Nothing in the repository mentions the AI tools used to build it: no commit trailers, file names, comments, docs or ignore rules. Local-only ignores for agent config files go in `.git/info/exclude`, never in `.gitignore`.
- Commit messages use plain imperative subjects with no attribution lines.
- No Arc code, icons, sounds or other assets in the repository. Test fixtures are synthetic. Never commit the owner's real Arc data.
- No telemetry and no network calls.
- Arc data is read-only. Nothing in this plan writes inside `~/Library/Application Support/Arc`.
- Brow stores its sidebar at `~/Library/Application Support/Brow/Sidebar.json`.

## Review focus

1. **A corrupt or half-written `Sidebar.json` at launch.** Brow must not overwrite it with an empty sidebar. It moves the bad file aside and reports it. (Task 2)
2. **Arc files from other Arc versions,** with unknown item kinds, extra keys or dangling child IDs. Import what's understood, warn about the rest, never fail the whole import. (Task 3)
3. **Snapshot while Arc is running.** Copying live databases gives a broken snapshot, so refuse unless overridden. (Task 4)
4. **Snapshot to a disk without enough space.** The owner's disk has about 8 GB free and Arc's folder is about 1.4 GB. Fail before copying, and never leave a partial copy that looks complete. (Task 4)
5. **Dragging a folder into its own subfolder.** Reject it and leave the document unchanged. (Task 1)

---

### Task 1: Package and sidebar model

**Files:**
- Create: `.gitignore`
- Create: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/SidebarModel/Identifiers.swift`
- Create: `app/Packages/Sources/SidebarModel/SidebarItem.swift`
- Create: `app/Packages/Sources/SidebarModel/Space.swift`
- Create: `app/Packages/Sources/SidebarModel/SidebarDocument.swift`
- Create: `app/Packages/Sources/SidebarModel/SidebarDocument+Editing.swift`
- Create: `app/Packages/Sources/SidebarModel/SidebarError.swift`
- Test: `app/Packages/Tests/SidebarModelTests/SidebarDocumentTests.swift`
- Modify: `.git/info/exclude` (local only, not committed)

**Interfaces:**
- Produces, all `public` and `Sendable`:
  - `struct ItemID: Hashable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible` wrapping `rawValue: String`, plus `static func make() -> ItemID` (UUID string). Encodes as a bare string.
  - `struct SpaceID`, same conformances and `make()`.
  - `struct SidebarItem: Codable, Equatable, Identifiable` with `id: ItemID`, `parentID: ItemID?`, `childIDs: [ItemID]`, `title: String?`, `createdAt: Date`, `isUnread: Bool`, `kind: SidebarItem.Kind`.
  - `enum SidebarItem.Kind: Codable, Equatable` with cases `tab(TabInfo)`, `folder(FolderInfo)`, `container(ContainerRole)`.
  - `struct TabInfo: Codable, Equatable` with `savedURL: URL?`, `savedTitle: String?`, `lastActiveAt: Date?`, `isMuted: Bool`.
  - `struct FolderInfo: Codable, Equatable` with `icon: String?`, `isExpanded: Bool`.
  - `enum ContainerRole: Codable, Equatable` with cases `pinned(SpaceID)`, `unpinned(SpaceID)`, `favorites`.
  - `struct Space: Codable, Equatable, Identifiable` with `id: SpaceID`, `title: String?`, `icon: String?`, `theme: SpaceTheme?`, `pinnedContainerID: ItemID`, `unpinnedContainerID: ItemID`.
  - `struct SpaceTheme: Codable, Equatable` with `primary: RGBAColor`. `struct RGBAColor: Codable, Equatable` with `red`, `green`, `blue`, `alpha: Double` in 0...1.
  - `struct SidebarDocument: Codable, Equatable` with `static let currentVersion = 1`, `version: Int`, `spaces: [Space]` (display order), `favoritesContainerID: ItemID`, and items stored privately as `[ItemID: SidebarItem]` but encoded as `items: [SidebarItem]` sorted by `id.rawValue`.
  - `SidebarDocument` methods: `init(version:spaces:favoritesContainerID:items:)` taking `items: [SidebarItem]`; `static func empty(now: Date) -> SidebarDocument`; `func item(_ id: ItemID) -> SidebarItem?`; `func children(of id: ItemID) -> [SidebarItem]`; `var allItems: [SidebarItem]`; `mutating func insert(_ item: SidebarItem, into parentID: ItemID, at index: Int?) throws`; `mutating func move(_ id: ItemID, to parentID: ItemID, at index: Int?) throws`; `mutating func remove(_ id: ItemID) throws -> [SidebarItem]`; `func validate() throws`.
  - `enum SidebarError: Error, Equatable` with cases `itemNotFound(ItemID)`, `duplicateItem(ItemID)`, `wouldCreateCycle(ItemID)`, `cannotMoveContainer(ItemID)`, `parentCannotHaveChildren(ItemID)`, `integrity(String)`, `unsupportedVersion(Int)`, `corruptFile(backupURL: URL)`.

- [ ] **Step 1: Create the package and ignore rules**

`Package.swift` declares package `BrowKit`, platform `.macOS(.v15)`, library product and target `SidebarModel`, test target `SidebarModelTests`. Later tasks add targets to this file.

`.gitignore` contains `.DS_Store`, `.build/`, `.swiftpm/`, `DerivedData/`, `xcuserdata/`, `*.xcuserstate`.

Append the agent config file and folder names to `.git/info/exclude`. That file is never committed.

- [ ] **Step 2: Write the failing tests**

In `SidebarDocumentTests.swift`, build a fixture document in a helper `makeDocument()` with one space `"S"` (pinned container `"P"`, unpinned `"U"`), favourites container `"F"`, folder `"folder"` inside `"P"`, folder `"sub"` inside `"folder"`, and tabs `"t1"` in `"P"` and `"t2"` in `"U"`. Tests:

```swift
@Test func emptyDocumentHasOneSpaceAndFavorites() throws {
    let doc = SidebarDocument.empty(now: Date(timeIntervalSince1970: 0))
    #expect(doc.spaces.count == 1)
    #expect(doc.item(doc.favoritesContainerID)?.kind == .container(.favorites))
    let space = doc.spaces[0]
    #expect(doc.item(space.pinnedContainerID)?.kind == .container(.pinned(space.id)))
    #expect(doc.item(space.unpinnedContainerID)?.kind == .container(.unpinned(space.id)))
    try doc.validate()
}

@Test func insertAtIndexUpdatesParentAndChild() throws {
    var doc = makeDocument()
    try doc.insert(tab("t3"), into: "P", at: 0)
    #expect(doc.item("P")?.childIDs == ["t3", "folder", "t1"])
    #expect(doc.item("t3")?.parentID == "P")
}

@Test func insertWithNilIndexAppends()             // childIDs of "P" == ["folder", "t1", "t3"]
@Test func insertClampsIndexPastEnd()              // index 99 appends
@Test func insertDuplicateIDThrows()               // throws .duplicateItem("t1")
@Test func insertIntoTabThrows()                   // into "t1" throws .parentCannotHaveChildren("t1")

@Test func moveTabBetweenSpacesContainers() throws {
    var doc = makeDocument()
    try doc.move("t1", to: "U", at: 0)
    #expect(doc.item("P")?.childIDs == ["folder"])
    #expect(doc.item("U")?.childIDs == ["t1", "t2"])
    #expect(doc.item("t1")?.parentID == "U")
}

@Test func moveWithinSameParentReorders()          // move "t1" to "P" at 0 -> ["t1", "folder"]

@Test func moveFolderIntoOwnDescendantIsRejected() throws {
    var doc = makeDocument()
    let before = doc
    #expect(throws: SidebarError.wouldCreateCycle("folder")) {
        try doc.move("folder", to: "sub", at: nil)
    }
    #expect(doc == before)
}

@Test func moveContainerIsRejected()               // move "P" throws .cannotMoveContainer("P")
@Test func removeFolderRemovesSubtree()            // remove("folder") returns ids {"folder","sub"}; neither present; "P".childIDs == ["t1"]
@Test func removeUnknownThrows()                   // .itemNotFound("nope")
@Test func validateCatchesParentMismatch()         // doc built via init with t1.parentID = "U" but listed in "P".childIDs -> throws .integrity
@Test func validateCatchesMissingSpaceContainer()  // space pointing at unknown container -> throws .integrity

@Test func roundTripsThroughJSON() throws {
    let doc = makeDocument()
    let data = try JSONEncoder().encode(doc)
    #expect(try JSONDecoder().decode(SidebarDocument.self, from: data) == doc)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter SidebarModelTests`
Expected: build fails because the types don't exist.

- [ ] **Step 4: Implement the types and editing methods**

`move` checks, in order: item exists, item isn't a container, target exists and is a container or folder, target isn't the item or one of its descendants. All checks happen before any mutation, so a failed call leaves the document unchanged. `validate()` checks that every child's `parentID` names its parent, every non-container has a parent, there are no cycles, and every space container and the favourites container exist with the matching `ContainerRole`. `empty(now:)` creates one untitled space.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter SidebarModelTests`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add .gitignore app/Packages
git commit -m "Add sidebar data model"
```

---

### Task 2: Sidebar JSON storage

**Files:**
- Create: `app/Packages/Sources/SidebarModel/SidebarDocumentStore.swift`
- Test: `app/Packages/Tests/SidebarModelTests/SidebarDocumentStoreTests.swift`

**Interfaces:**
- Consumes: `SidebarDocument`, `SidebarError` from Task 1.
- Produces: `public struct SidebarDocumentStore: Sendable` with `init(fileURL: URL)`, `static func defaultFileURL() throws -> URL` (returns `~/Library/Application Support/Brow/Sidebar.json`, creating the `Brow` folder), `func load(now: Date = .now) throws -> SidebarDocument?`, `func save(_ document: SidebarDocument) throws`.

- [ ] **Step 1: Write the failing tests**

Each test uses a fresh temporary directory.

```swift
@Test func loadReturnsNilWhenFileMissing()          // load() == nil
@Test func saveThenLoadRoundTrips()                 // equal documents
@Test func saveWritesSortedPrettyJSON()             // file text contains "\"version\" : 1" and items sorted by id

@Test func corruptFileIsMovedAsideNotOverwritten() throws {
    let url = dir.appending(path: "Sidebar.json")
    try Data("{ not json".utf8).write(to: url)
    let store = SidebarDocumentStore(fileURL: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(throws: SidebarError.corruptFile(backupURL: dir.appending(path: "Sidebar.corrupt-20270115-080000.json"))) {
        try store.load(now: now)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(try String(contentsOf: dir.appending(path: "Sidebar.corrupt-20270115-080000.json"), encoding: .utf8) == "{ not json")
}

@Test func futureVersionThrowsAndLeavesFileInPlace() // file with "version": 2 -> throws .unsupportedVersion(2); file still exists
@Test func structurallyInvalidFileIsTreatedAsCorrupt() // valid JSON that fails validate() -> .corruptFile, moved aside
```

The backup timestamp is UTC, format `yyyyMMdd-HHmmss`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter SidebarDocumentStoreTests`
Expected: build fails because `SidebarDocumentStore` doesn't exist.

- [ ] **Step 3: Implement `SidebarDocumentStore`**

Encoder settings: `.prettyPrinted`, `.sortedKeys`, dates `.secondsSince1970`. Save with `Data.write(to:options: .atomic)`. `load` reads `version` first with a small decodable header, so a future version is reported as `unsupportedVersion` before a full decode is attempted. Decode failures and `validate()` failures both move the file aside and throw `corruptFile`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter SidebarModelTests`
Expected: all tests pass, including Task 1's.

- [ ] **Step 5: Commit**

```bash
git add app/Packages
git commit -m "Add sidebar JSON storage"
```

---

### Task 3: Arc sidebar importer

**Files:**
- Modify: `app/Packages/Package.swift` (add library target `ArcImport` depending on `SidebarModel`, test target `ArcImportTests` with resources `.copy("Fixtures")`)
- Create: `app/Packages/Sources/ArcImport/ArcDataLocation.swift`
- Create: `app/Packages/Sources/ArcImport/ArcStorableSidebar.swift` (Decodable mirror of Arc's file)
- Create: `app/Packages/Sources/ArcImport/AlternatingPairs.swift`
- Create: `app/Packages/Sources/ArcImport/ArcSidebarImporter.swift`
- Create: `app/Packages/Tests/ArcImportTests/Fixtures/StorableSidebar.json`
- Test: `app/Packages/Tests/ArcImportTests/ArcSidebarImporterTests.swift`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - `public struct ArcDataLocation: Sendable` with `init(root: URL)`, `static var live: ArcDataLocation` (`~/Library/Application Support/Arc`), `var sidebarFileURL: URL` (`root/StorableSidebar.json`). A snapshot folder from Task 4 has the same layout, so `init(root:)` works for both.
  - `public struct ArcSidebarImporter: Sendable` with `init()` and `func importSidebar(from fileURL: URL) throws -> ArcImportResult`.
  - `public struct ArcImportResult: Sendable` with `document: SidebarDocument` and `warnings: [ArcImportWarning]`.
  - `public enum ArcImportWarning: Equatable, Sendable` with cases `unsupportedItem(id: ItemID, kind: String)`, `danglingChild(parent: ItemID, child: ItemID)`, `unreachableItems(count: Int)`, `missingFavorites`.
  - `public enum ArcImportError: Error, Equatable` with cases `fileNotFound(URL)`, `malformed(String)`, `noSpaces`.

**What Arc's file looks like** (from the teardown of Arc 1.169.0):

- Top level: `version`, `sidebar.containers` (array). Use the first container object that has a `spaces` key. Don't rely on its index.
- `items`, `spaces` and `topAppsContainerIDs` are flat arrays alternating key and value: `[key, value, key, value, ...]`. `AlternatingPairs<Key: Decodable, Value: Decodable>` decodes these and throws `malformed` on odd length.
- Item: `id`, `parentID` (nullable), `childrenIds`, `title` (nullable), `createdAt`, `isUnread`, `data`. `data` has exactly one key: `tab`, `list` or `itemContainer`. Any other key is an unsupported kind.
- `data.tab` fields, all optional: `savedURL`, `savedTitle`, `timeLastActiveAt`, `savedMuteStatus`. Ignore `activeTabBeforeCreationID` and `referrerID`.
- `data.list.customInfo.iconType.icon` is an optional emoji string.
- `data.itemContainer.containerType` is `{"spaceItems": {"_0": "<spaceID>"}}` for a space container or `{"topApps": {"_0": {"default": true}}}` for favourites.
- Space: `id`, optional `title`, `customInfo.iconType.icon` (optional), `containerIDs` alternating label and ID, like `["pinned", "<id>", "unpinned", "<id>"]`. Use `containerIDs` to decide which container is pinned and which is unpinned.
- `topAppsContainerIDs`: `[{"default": true}, "<containerID>"]`. The container paired with `{"default": true}` is favourites.
- All timestamps are seconds since 1 January 2001. Convert with `Date(timeIntervalSinceReferenceDate:)`.
- Ignore unknown keys everywhere.

**Mapping rules:**
- Arc item IDs and space IDs become Brow IDs unchanged.
- Space order follows the `spaces` array.
- `isMuted` is true only when `savedMuteStatus == "muted"`.
- `FolderInfo.isExpanded` is `true`.
- Walk from each space's two containers and the favourites container. Drop anything not reachable, and report the count once as `unreachableItems`. Drop child IDs with no matching item (`danglingChild`). Drop unsupported items and their subtrees (`unsupportedItem` for the root of each).
- No favourites container means create an empty one and warn `missingFavorites`.
- The result must pass `validate()`.

- [ ] **Step 1: Write the fixture**

`Fixtures/StorableSidebar.json`, synthetic:

```json
{
  "version": 1,
  "sidebar": { "containers": [
    { "global": {} },
    {
      "topAppsContainerIDs": [ { "default": true }, "fav-root" ],
      "spaces": [
        "space-A", { "id": "space-A", "title": "Work", "profile": { "default": true },
                     "customInfo": { "iconType": { "icon": "💼" } },
                     "containerIDs": [ "pinned", "A-pinned", "unpinned", "A-unpinned" ] },
        "space-B", { "id": "space-B", "profile": { "default": true }, "customInfo": {},
                     "containerIDs": [ "pinned", "B-pinned", "unpinned", "B-unpinned" ] }
      ],
      "items": [
        "fav-root", { "id": "fav-root", "parentID": null, "childrenIds": [ "fav-1" ], "title": null, "createdAt": 700000000.0, "isUnread": false,
                      "data": { "itemContainer": { "containerType": { "topApps": { "_0": { "default": true } } } } } },
        "fav-1", { "id": "fav-1", "parentID": "fav-root", "childrenIds": [], "title": "Mail", "createdAt": 700000001.0, "isUnread": false,
                   "data": { "tab": { "savedURL": "https://mail.example.com/", "savedTitle": "Mail", "timeLastActiveAt": 790000000.0, "savedMuteStatus": "allowAudio" } } },
        "A-pinned", { "id": "A-pinned", "parentID": null, "childrenIds": [ "folder-1", "tab-p2" ], "title": null, "createdAt": 700000000.0, "isUnread": false,
                      "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "space-A" } } } } },
        "folder-1", { "id": "folder-1", "parentID": "A-pinned", "childrenIds": [ "tab-p1", "missing-id" ], "title": "Projects", "createdAt": 700000002.0, "isUnread": false,
                      "data": { "list": { "customInfo": { "iconType": { "icon": "📁" } } } } },
        "tab-p1", { "id": "tab-p1", "parentID": "folder-1", "childrenIds": [], "title": null, "createdAt": 700000003.0, "isUnread": true,
                    "data": { "tab": { "savedURL": "https://docs.example.com/", "savedTitle": "Docs", "referrerID": "x" } } },
        "tab-p2", { "id": "tab-p2", "parentID": "A-pinned", "childrenIds": [], "title": "My calendar", "createdAt": 700000004.0, "isUnread": false,
                    "data": { "tab": { "savedURL": "https://calendar.example.com/", "savedTitle": "Calendar", "savedMuteStatus": "muted" } } },
        "A-unpinned", { "id": "A-unpinned", "parentID": null, "childrenIds": [ "tab-u1", "easel-1" ], "title": null, "createdAt": 700000000.0, "isUnread": false,
                        "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "space-A" } } } } },
        "tab-u1", { "id": "tab-u1", "parentID": "A-unpinned", "childrenIds": [], "title": null, "createdAt": 700000005.0, "isUnread": false,
                    "data": { "tab": { "savedURL": "https://news.example.com/", "timeLastActiveAt": 790100000.0 } } },
        "easel-1", { "id": "easel-1", "parentID": "A-unpinned", "childrenIds": [], "title": "Board", "createdAt": 700000006.0, "isUnread": false,
                     "data": { "easel": {} } },
        "B-pinned", { "id": "B-pinned", "parentID": null, "childrenIds": [], "title": null, "createdAt": 700000000.0, "isUnread": false,
                      "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "space-B" } } } } },
        "B-unpinned", { "id": "B-unpinned", "parentID": null, "childrenIds": [], "title": null, "createdAt": 700000000.0, "isUnread": false,
                        "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "space-B" } } } } },
        "orphan-1", { "id": "orphan-1", "parentID": "gone", "childrenIds": [], "title": null, "createdAt": 700000007.0, "isUnread": false,
                      "data": { "tab": { "savedURL": "https://orphan.example.com/" } } }
      ]
    }
  ] },
  "firebaseSyncState": { "ignored": true }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
@Test func importsSpacesInOrder() throws {
    let result = try importFixture()
    #expect(result.document.spaces.map(\.id) == ["space-A", "space-B"])
    #expect(result.document.spaces[0].title == "Work")
    #expect(result.document.spaces[0].icon == "💼")
    #expect(result.document.spaces[1].title == nil)
    #expect(result.document.spaces[0].pinnedContainerID == "A-pinned")
    #expect(result.document.spaces[0].unpinnedContainerID == "A-unpinned")
}

@Test func importsFavorites() throws {
    let doc = try importFixture().document
    #expect(doc.favoritesContainerID == "fav-root")
    #expect(doc.children(of: "fav-root").map(\.id) == ["fav-1"])
    guard case .tab(let info) = doc.item("fav-1")?.kind else { Issue.record("not a tab"); return }
    #expect(info.savedURL == URL(string: "https://mail.example.com/"))
    #expect(info.lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_000_000))
    #expect(info.isMuted == false)
}

@Test func importsPinnedFoldersAndTabs()   // children(of: "A-pinned") ids == ["folder-1", "tab-p2"]; folder-1 kind == .folder(FolderInfo(icon: "📁", isExpanded: true)), title "Projects"; children(of: "folder-1") == ["tab-p1"]; tab-p1 isUnread == true; tab-p2 title == "My calendar" and isMuted == true
@Test func importsUnpinnedTabs()           // children(of: "A-unpinned") ids == ["tab-u1"]; tab-u1 lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_100_000)
@Test func reportsWarnings() throws {
    let warnings = try importFixture().warnings
    #expect(warnings.contains(.danglingChild(parent: "folder-1", child: "missing-id")))
    #expect(warnings.contains(.unsupportedItem(id: "easel-1", kind: "easel")))
    #expect(warnings.contains(.unreachableItems(count: 1)))
    #expect(warnings.count == 3)
}
@Test func resultValidates()               // try result.document.validate() does not throw
@Test func missingFileThrows()             // .fileNotFound(url)
@Test func oddLengthItemsArrayIsMalformed() // fixture text with "items": ["only-key"] throws .malformed
@Test func fileWithoutSpacesThrows()       // containers [{"global":{}}] throws .noSpaces
@Test func missingFavoritesCreatesEmptyContainer() // remove topAppsContainerIDs and fav items; warnings contains .missingFavorites; favourites container exists with no children
```

Variant fixtures in the last three tests are built in code from small JSON strings written to a temporary directory.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter ArcImportTests`
Expected: build fails because `ArcImport` doesn't exist.

- [ ] **Step 4: Implement the importer**

Decode Arc's file into `ArcStorableSidebar` types that mirror the shapes above, keeping `data` as an enum with an `unsupported(String)` case so one unknown item doesn't fail the decode. Then build `SidebarItem`s by walking from the three container roots.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add Arc sidebar importer"
```

---

### Task 4: Arc snapshot

**Files:**
- Modify: `app/Packages/Package.swift` (add library target `ArcSnapshot`, test target `ArcSnapshotTests`)
- Create: `app/Packages/Sources/ArcSnapshot/ArcSnapshotter.swift`
- Create: `app/Packages/Sources/ArcSnapshot/SnapshotManifest.swift`
- Test: `app/Packages/Tests/ArcSnapshotTests/ArcSnapshotterTests.swift`

**Interfaces:**
- Produces:
  - `public struct ArcSnapshotter: Sendable` with `init(source: URL, destinationRoot: URL, arcVersion: String?, isArcRunning: @Sendable () -> Bool, availableCapacity: @Sendable (URL) throws -> Int64)` and `func run(now: Date, allowWhileRunning: Bool = false) throws -> SnapshotResult`.
  - `public static let excludedDirectoryNames: Set<String>` = `["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "component_crx_cache", "Crashpad"]`, matched as directory names at any depth.
  - `public struct SnapshotResult: Sendable` with `folderURL: URL`, `manifest: SnapshotManifest`.
  - `public struct SnapshotManifest: Codable, Equatable, Sendable` with `createdAt: Date`, `sourcePath: String`, `arcVersion: String?`, `fileCount: Int`, `totalBytes: Int64`, `skippedSpecialFiles: Int`.
  - `public enum ArcSnapshotError: Error, Equatable` with `sourceMissing(URL)`, `arcIsRunning`, `insufficientSpace(needed: Int64, available: Int64)`, `destinationExists(URL)`.

**Behaviour:**
- The final folder is `<destinationRoot>/Arc-snapshot-<yyyyMMdd-HHmmss UTC>`. Copy into `<that name>.partial` first and rename on success. On failure, delete the `.partial` folder.
- Space check before copying: needed = total size of files that will be copied, plus 10%. Fail with `insufficientSpace` if available is less than that.
- Copy regular files and directories. Copy symlinks as symlinks. Skip sockets and other special files and count them in `skippedSpecialFiles`.
- Write `snapshot-manifest.json` in the snapshot folder (pretty-printed, sorted keys, ISO 8601 dates).
- Never write inside `source`.

- [ ] **Step 1: Write the failing tests**

Each test builds a fake Arc folder in a temporary directory: `StorableSidebar.json` (10 bytes), `User Data/Default/History` (20 bytes), `User Data/Default/Cache/data_0` (1000 bytes), `User Data/Default/Code Cache/js/x` (1000 bytes), and a symlink `User Data/SingletonLock -> host-123`.

```swift
@Test func copiesDataAndSkipsCaches() throws {
    let result = try makeSnapshotter().run(now: fixedNow)
    #expect(result.folderURL.lastPathComponent == "Arc-snapshot-20270115-080000")
    #expect(exists(result.folderURL, "StorableSidebar.json"))
    #expect(exists(result.folderURL, "User Data/Default/History"))
    #expect(!exists(result.folderURL, "User Data/Default/Cache"))
    #expect(!exists(result.folderURL, "User Data/Default/Code Cache"))
    #expect(isSymlink(result.folderURL, "User Data/SingletonLock"))
    #expect(result.manifest.fileCount == 2)
    #expect(result.manifest.totalBytes == 30)
}
@Test func writesManifestFile()               // decoded snapshot-manifest.json == result.manifest; arcVersion == "1.169.0"
@Test func refusesWhileArcRunning()           // isArcRunning returns true -> throws .arcIsRunning; destinationRoot has no entries
@Test func allowWhileRunningOverrides()       // same, with allowWhileRunning: true -> succeeds
@Test func insufficientSpaceFailsBeforeCopying() // availableCapacity returns 20 -> throws .insufficientSpace(needed: 33, available: 20); destinationRoot has no entries
@Test func missingSourceThrows()              // .sourceMissing
@Test func existingSnapshotFolderThrows()     // pre-create Arc-snapshot-20270115-080000 -> .destinationExists
@Test func sourceIsUnchanged()                // recursive listing of source with sizes and modification dates is identical before and after
```

`fixedNow` is `Date(timeIntervalSince1970: 1_800_000_000)`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter ArcSnapshotTests`
Expected: build fails because `ArcSnapshot` doesn't exist.

- [ ] **Step 3: Implement `ArcSnapshotter`**

Walk the source once to plan the copy (file list, total size, special files) so the space check runs before any write. Use `FileManager.enumerator(at:includingPropertiesForKeys:)` with `.isRegularFileKey`, `.isDirectoryKey`, `.isSymbolicLinkKey`, `.fileSizeKey`, and `skipDescendants()` for excluded directories.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/Packages
git commit -m "Add Arc data snapshot"
```

---

### Task 5: `brow-arc` command-line tool and README

**Files:**
- Modify: `app/Packages/Package.swift` (add executable target and product `brow-arc` depending on `ArcImport`, `ArcSnapshot`, `SidebarModel`)
- Create: `app/Packages/Sources/brow-arc/main.swift`
- Create: `app/Packages/Sources/brow-arc/InspectReport.swift`
- Test: `app/Packages/Tests/ArcImportTests/InspectReportTests.swift` (move `InspectReport` into `ArcImport` if the test target can't reach an executable target. A library home is fine.)
- Modify: `README.md`

**Interfaces:**
- Consumes: `ArcSidebarImporter`, `ArcDataLocation`, `ArcSnapshotter`, `SnapshotManifest`.
- Produces: `public func inspectReport(_ result: ArcImportResult) -> String`.

**Commands:**
- `brow-arc snapshot <destination-folder> [--allow-running]`. Source is `ArcDataLocation.live.root`. `arcVersion` comes from `/Applications/Arc.app/Contents/Info.plist` `CFBundleShortVersionString` if present. `isArcRunning` checks `NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.Browser")`. `availableCapacity` reads `.volumeAvailableCapacityForImportantUsageKey`. On success, print the snapshot path, file count and size in GB to one decimal place.
- `brow-arc inspect [--root <folder>]`. Default root is the live Arc folder. Prints `inspectReport` to stdout. Doesn't write anything.
- Errors print one plain line to stderr and exit with status 1. Example: `Arc is running. Quit Arc first, or pass --allow-running.` Usage errors exit with status 2.

- [ ] **Step 1: Write the failing test**

```swift
@Test func reportSummarisesFixture() throws {
    let report = inspectReport(try importFixture())
    #expect(report == """
    Spaces: 2
      Work: 2 pinned (1 folder), 1 unpinned
      Untitled space: 0 pinned (0 folders), 0 unpinned
    Favourites: 1
    Warnings: 3
      Skipped unsupported item easel-1 (easel)
      Dropped missing child missing-id from folder-1
      Dropped 1 item not reachable from any space
    """)
}
```

Pinned counts are tabs anywhere under the pinned container. Folder counts are folders anywhere under it. Use "folder" when the count is 1. Warnings are listed in the order shown.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path app/Packages --filter InspectReportTests`
Expected: build fails because `inspectReport` doesn't exist.

- [ ] **Step 3: Implement `inspectReport` and `main.swift`**

Parse `CommandLine.arguments` by hand. No argument-parser dependency.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages`
Expected: all tests pass.

- [ ] **Step 5: Check the import against the owner's real Arc data**

Run: `swift run --package-path app/Packages brow-arc inspect`
Expected: `Spaces: 3`, with pinned and unpinned counts that match what the owner sees in Arc's sidebar. Show the output to the owner and confirm before moving on. Any warnings get a look, but they don't block.

- [ ] **Step 6: Take the owner's snapshot**

Ask the owner to quit Arc and name the destination, which should be their external drive. Then run: `swift run --package-path app/Packages brow-arc snapshot "<destination>"`
Expected: prints a path ending in `Arc-snapshot-<timestamp>`, at least 1 GB. Then run `swift run --package-path app/Packages brow-arc inspect --root "<printed path>"` and check that its report matches Step 5's.

- [ ] **Step 7: Update the README**

Add: one paragraph on what Brow is, the folder layout from the design doc (marking `chromium/` as coming later), how to run the tests (`swift test --package-path app/Packages`), and the two `brow-arc` commands.

- [ ] **Step 8: Commit**

```bash
git add app/Packages README.md
git commit -m "Add brow-arc snapshot and inspect commands"
```
