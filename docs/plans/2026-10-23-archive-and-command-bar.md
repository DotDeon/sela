# Archive and command bar implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** Unpinned tabs archive themselves after 12 hours of inactivity into a searchable archive. Cmd+T and Cmd+L open Arc's command bar, which finds open tabs, archived tabs, history and commands, and opens addresses or searches.

**Architecture:** Three new modules:
- `Archive` stores archived tabs in `Archive.json` and decides which tabs are due.
- `History` keeps visited pages in SQLite.
- `CommandBar` ranks results from plain candidate lists and draws an overlay panel. It knows nothing about the stores, so the app maps sidebar tabs, archive entries and history entries into candidates.

`BrowserWindowModel` archives tabs instead of deleting them, and reports finished page loads so the app can record history.

**Tech stack:** Swift 6 language mode, SwiftPM, Swift Testing, AppKit, Observation, SQLite through the system `SQLite3` module. No third-party dependencies.

**Spec:** `docs/design/2026-10-23-brow-design.md`, trait 3 ("Unpinned tabs archive themselves"), the "Command bar" goal, milestone 4, and step 5 of "Order before the new Mac arrives". Split view and Peek, also in milestone 4, get their own plan next.

## Global constraints

- Everything from the earlier plans still applies: macOS 15 floor, tools version 6.0, no AI tool mentions anywhere in the repository, plain imperative commit subjects with no attribution lines, no Arc assets, no telemetry, no WebKit import outside `WebKitEngine`.
- Unpinned tabs archive after 12 hours without being selected by default, matching Arc. The choices are 12 hours, 24 hours, 7 days, 30 days and Never, stored in `UserDefaults` key `ArchiveAfterHours` (0 means never).
- A tab's inactivity starts from `lastActiveAt`, or `createdAt` when it has never been selected.
- The archive keeps entries for 30 days and at most 1,000 entries. History keeps 90 days, like Chrome.
- Files: `~/Library/Application Support/Brow/Archive.json` and `~/Library/Application Support/Brow/History.sqlite`.
- No network calls for the command bar. Remote search suggestions are out of scope.
- Shortcuts follow Arc: Cmd+T opens the command bar for a new tab, Cmd+L opens it for the current tab with the address selected, Cmd+Shift+T reopens the most recently archived tab. Up and Down move, Return opens, Escape closes.
- Closing an unpinned tab (Cmd+W, the row's close button, "Clear", or the page calling `window.close()`) archives it instead of losing it.

## Review focus

1. **The tab you're reading.** A tab that's selected in any window is never archived, even when it's been open for days with no other activity. (Task 1)
2. **Waking the Mac after a night asleep.** The first sweep after waking archives every overdue tab at once. Tabs opened in the background and never selected count from when they were created. (Task 1)
3. **Typing a tab's name.** "inbox" with an "Inbox – Gmail" tab open should put that tab first, so Return switches to it. "what is swift" should put the search first. (Task 4)
4. **Search text with SQL wildcards.** Typing `100%` or `_` mustn't match every history entry. (Task 2)
5. **Reopening.** Cmd+Shift+T with an empty archive does nothing. A tab whose space has since been deleted reopens in the current space. (Task 3)

---

### Task 1: Archive store and inactive tab sweep

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/Archive/ArchiveEntry.swift`
- Create: `app/Packages/Sources/Archive/ArchiveStore.swift`
- Create: `app/Packages/Sources/Archive/InactiveTabs.swift`
- Test: `app/Packages/Tests/ArchiveTests/ArchiveStoreTests.swift`
- Test: `app/Packages/Tests/ArchiveTests/InactiveTabsTests.swift`

**Interfaces:**
- Consumes: `SidebarStore`, `SidebarDocument` and `BrowTestSupport.fixtureDocument()`.
- Produces, in the new `Archive` module:
  - `struct ArchiveEntry: Codable, Equatable, Identifiable, Sendable` with `id: UUID`, `url: URL?`, `title: String?`, `spaceID: SpaceID?`, `archivedAt: Date`.
  - `@MainActor @Observable final class ArchiveStore` with:
    - `init(fileURL: URL, now: @escaping @MainActor () -> Date = { .now })`
    - `private(set) var entries: [ArchiveEntry]`, newest first.
    - `func add(_ entries: [ArchiveEntry])`
    - `@discardableResult func remove(_ id: UUID) -> ArchiveEntry?`
    - `func search(_ query: String) -> [ArchiveEntry]`
    - `static func defaultFileURL() throws -> URL`
  - `func inactiveTabs(in document: SidebarDocument, now: Date, after interval: TimeInterval, protecting: Set<ItemID>) -> [ItemID]` returns unpinned tabs in every space.
  - `@MainActor @discardableResult func archiveInactiveTabs(sidebar: SidebarStore, archive: ArchiveStore, now: Date, after interval: TimeInterval, protecting: Set<ItemID>) -> [ItemID]`
  - `@MainActor func archiveEntry(for id: ItemID, in document: SidebarDocument, at date: Date) -> ArchiveEntry?`, used here and by Task 3.

Rules:

- `ArchiveStore` writes atomically on every change, since changes are rare and come in batches.
- On load and on `add`, it drops entries older than 30 days and keeps only the newest 1,000.
- A file that can't be decoded is moved to `Archive.corrupt-<yyyyMMdd-HHmmss>.json`, and the store starts empty.
- `search` matches every word of the query, case-insensitively, against the title and URL. A blank query returns everything.

- [ ] **Step 1: Add the targets**

Library product and target `Archive` (depends on `Sidebar`, `SidebarModel`). Test target `ArchiveTests` (depends on `Archive`, `Sidebar`, `SidebarModel`, `BrowTestSupport`).

- [ ] **Step 2: Write the failing tests**

```swift
// ArchiveStoreTests
@Test func addedEntriesComeNewestFirst()
@Test func entriesSurviveReload()                 // new ArchiveStore on the same file sees them
@Test func oldEntriesArePruned()                  // entry archived 31 days before now is dropped; 29 days kept
@Test func atMostOneThousandEntries()             // add 1,005 -> 1,000, the newest
@Test func removeReturnsTheEntry()
@Test func searchMatchesEveryWord()               // "swift docs" matches "Swift Docs – Apple", not "Swift Forums"
@Test func corruptFileIsMovedAside()              // "{ nope" -> entries empty, backup file exists

// InactiveTabsTests, fixture now = fixtureDate + 13 hours, interval 12 hours
@Test func staleUnpinnedTabsAreDue()              // u1 (active at fixtureDate) and u2 (fixtureDate+10s) -> both due
@Test func pinnedAndFavoritesAreNeverDue()        // p1, p2, q1, f1 never returned even with lastActiveAt long ago
@Test func protectedTabsAreNotDue()               // protecting ["u2"] -> ["u1"]
@Test func neverSelectedTabsCountFromCreation()   // tab with lastActiveAt nil and createdAt 2 hours ago is not due; 13 hours ago is due
@Test func archivingMovesTabsIntoTheArchive()     // archiveInactiveTabs -> sidebar no longer has u1/u2; archive has 2 entries with their URLs, titles and spaceID "S"
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter ArchiveTests`
Expected: build fails.

- [ ] **Step 4: Implement the store and the sweep**

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter ArchiveTests`
Expected: 12 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add tab archive and inactive tab sweep"
```

---

### Task 2: History store

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/History/HistoryStore.swift`
- Test: `app/Packages/Tests/HistoryTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces, in the new `History` module:
  - `struct HistoryEntry: Equatable, Sendable` with `url: URL`, `title: String?`, `visitCount: Int`, `lastVisitedAt: Date`.
  - `@MainActor final class HistoryStore` with:
    - `init(fileURL: URL, now: @escaping @MainActor () -> Date = { .now }) throws`
    - `func recordVisit(url: URL, title: String?)`
    - `func search(_ query: String, limit: Int) -> [HistoryEntry]`
    - `func clear()`
    - `static func defaultFileURL() throws -> URL`

Rules:

- The schema is one table: `visits(url TEXT PRIMARY KEY, title TEXT, visit_count INTEGER, last_visited REAL)`.
- `recordVisit` inserts or bumps `visit_count`, updates `last_visited`, and replaces the title when one is given. It ignores anything that isn't http or https.
- `search` requires every word to appear in `url || ' ' || title`, using `LIKE ... ESCAPE '\'` with `%`, `_` and `\` escaped. Results sort by `last_visited` descending. A blank query returns the most recent.
- On open, entries whose last visit is more than 90 days old are deleted.

- [ ] **Step 1: Add the targets**

Library product and target `History` (no dependencies; it links `sqlite3` with `linkerSettings: [.linkedLibrary("sqlite3")]`). Test target `HistoryTests`.

- [ ] **Step 2: Write the failing tests**

```swift
@Test func visitsAreCountedAndTitled()      // record a twice (second with title "A") -> visitCount 2, title "A"
@Test func searchNeedsEveryWord()           // "swift forum" finds forums.swift.org page titled "Swift Forums", not swift.org "Swift"
@Test func wildcardsAreLiteral()            // pages "100% done" and "plain"; search "100%" -> only the first; search "_" -> none
@Test func recentFirstAndLimited()          // 3 visits at increasing times, limit 2 -> newest two in order
@Test func nonWebAddressesAreIgnored()      // file:// and about:blank -> nothing stored
@Test func oldVisitsArePrunedOnOpen()       // visit 91 days ago is gone after reopening; 89 days kept
@Test func clearRemovesEverything()
@Test func historySurvivesReopen()
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter HistoryTests`
Expected: build fails.

- [ ] **Step 4: Implement `HistoryStore`**

Use `import SQLite3` with prepared statements, and bind text with `SQLITE_TRANSIENT`. Enable WAL journal mode.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter HistoryTests`
Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add browsing history store"
```

---

### Task 3: Archiving and visits in the window model

**Files:**
- Modify: `app/Packages/Package.swift` (`Browsing` gains `Archive`)
- Modify: `app/Packages/Sources/Browsing/BrowserWindowModel.swift`
- Test: `app/Packages/Tests/BrowsingTests/BrowserWindowArchiveTests.swift`

**Interfaces:**
- Consumes: Task 1's `ArchiveStore`, `ArchiveEntry` and `archiveEntry(for:in:at:)`.
- Produces, on `BrowserWindowModel`:
  - The init gains `archive: ArchiveStore? = nil`. Existing callers and tests stay valid.
  - `var onPageVisited: ((URL, String?) -> Void)?` is called once each time a tab finishes loading a new http or https address, with the title it has then.
  - `func restore(_ entryID: UUID)` removes the entry and creates an unpinned tab at the top of the entry's space, or the current space if that space is gone. It loads the entry's URL and selects the tab.
  - `func reopenLastArchived()` restores `archive.entries.first`, and does nothing when the archive is empty or missing.
  - `close(_:)` and `clearUnpinned()` add an `ArchiveEntry` for every unpinned tab they remove. For live tabs, the entry uses the live page's current URL and title.

- [ ] **Step 1: Write the failing tests**

Reuse the Task 5 harness from the sidebar plan, extended to pass an `ArchiveStore` on a temporary file.

```swift
@Test func closingUnpinnedArchivesIt()           // close(u1) -> archive.entries.first?.url == u1 URL, spaceID "S"
@Test func closingPinnedDoesNotArchive()
@Test func clearArchivesEveryUnpinnedTab()       // 2 entries
@Test func archiveUsesTheLivePage()              // u1 live, navigated to other + finishLoading("Other") -> entry url other, title "Other"
@Test func restoreReopensAtTopOfItsSpace()       // close u1, restore entry -> unpinned first child has u1 URL, selected, entry gone
@Test func restoreIntoDeletedSpaceUsesCurrent()  // entry for S2, removeSpace(S2), restore -> lands in S's unpinned
@Test func reopenWithEmptyArchiveDoesNothing()
@Test func visitsAreReportedOncePerPage()        // load a, finishLoading("A") -> [(a, "A")]; finishLoading again with favicon -> still 1; load b + finish -> 2; about:blank -> no call
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter BrowserWindowArchiveTests`
Expected: build fails.

- [ ] **Step 3: Implement**

Keep a `[TabID: URL]` of the last reported visit per tab. Report when `isLoading` is false, the URL is http or https, and it differs from the last one reported for that tab.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter BrowsingTests`
Expected: all pass, including the 33 existing tests.

- [ ] **Step 5: Commit**

```bash
git add app/Packages
git commit -m "Archive closed tabs and report visits"
```

---

### Task 4: Command bar ranking and model

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/CommandBar/CommandBarCandidates.swift`
- Create: `app/Packages/Sources/CommandBar/CommandBarRanking.swift`
- Create: `app/Packages/Sources/CommandBar/CommandBarModel.swift`
- Test: `app/Packages/Tests/CommandBarTests/CommandBarRankingTests.swift`
- Test: `app/Packages/Tests/CommandBarTests/CommandBarModelTests.swift`

**Interfaces:**
- Consumes: `AddressInput` from `Browsing`, and `ItemID` from `SidebarModel`.
- Produces, in the new `CommandBar` module:
  - Candidates:
    - `struct TabCandidate: Equatable, Sendable` with `id: ItemID`, `title: String`, `url: URL?`, `lastActiveAt: Date?`
    - `struct CommandCandidate: Equatable, Sendable` with `id: String`, `title: String`, `keywords: [String]`
    - `struct ArchivedCandidate: Equatable, Sendable` with `id: UUID`, `title: String`, `url: URL?`
    - `struct HistoryCandidate: Equatable, Sendable` with `url: URL`, `title: String`
  - `enum CommandBarResult: Equatable, Sendable`:
    - `.open(URL, isSearch: Bool)`
    - `.tab(TabCandidate)`
    - `.command(CommandCandidate)`
    - `.archived(ArchivedCandidate)`
    - `.history(HistoryCandidate)`
  - `func matchScore(_ query: String, _ text: String) -> Int?`
  - `func commandBarResults(query: String, tabs: [TabCandidate], commands: [CommandCandidate], archived: [ArchivedCandidate], history: [HistoryCandidate]) -> [CommandBarResult]`
  - `enum CommandBarMode: Equatable, Sendable { case newTab, currentTab(address: String) }`
  - `enum CommandBarAction: Equatable, Sendable`:
    - `.open(URL, inNewTab: Bool)`
    - `.selectTab(ItemID)`
    - `.runCommand(String)`
    - `.restoreArchived(UUID)`
  - `struct CommandBarSources`: `tabs: () -> [TabCandidate]`, `commands: [CommandCandidate]`, `archived: (String) -> [ArchivedCandidate]`, `history: (String) -> [HistoryCandidate]`.
  - `@MainActor @Observable final class CommandBarModel` with:
    - `init(mode: CommandBarMode, sources: CommandBarSources)`
    - `var query: String`, which recomputes `results` when set. In `.currentTab` mode it starts as the address.
    - `private(set) var results: [CommandBarResult]`, `private(set) var selectedIndex: Int`
    - `func moveSelection(by offset: Int)` (clamped, no wrap)
    - `func activate(at index: Int? = nil) -> CommandBarAction?`

Rules:

- **`matchScore`.** Compare lower-cased. Strip `https://`, `http://` and `www.` from the text. Every whitespace-separated query word must appear. A word that starts a word of the text scores 2, anywhere else scores 1. The total is the sum, and nil when any word is missing.
- **Order.** The `.open` row comes from `AddressInput.resolve`; `isSearch` is true when the result's URL starts with Google's search prefix. Then come up to 5 tabs, 3 commands, 3 archived and 5 history rows. Each group is sorted by score, with recency or input order breaking ties.
- **Top hit.** When the best tab scores 2 for every query word, that tab goes before the `.open` row.
- **Duplicates.** History and archived rows whose URL matches an open tab's URL are dropped.
- **Empty query.** No `.open` row, and the 6 most recently active tabs.
- **Activating.** In `.newTab` mode, `.open` becomes `.open(url, inNewTab: true)`. In `.currentTab` mode it's `inNewTab: false`. Selection starts at 0 after every query change.

- [ ] **Step 1: Add the targets**

Library product and target `CommandBar` (depends on `Browsing`, `SidebarModel`). Test target `CommandBarTests`.

- [ ] **Step 2: Write the failing tests**

```swift
// CommandBarRankingTests
@Test(arguments: [("inb", "Inbox – Gmail", 2), ("box", "Inbox", 1), ("mail inbox", "Inbox – Gmail", 4), ("github", "https://www.github.com/x", 2), ("zzz", "Inbox", nil)])
func scores(query: String, text: String, expected: Int?)
@Test func strongTabMatchComesFirst()           // "inbox" with tab "Inbox – Gmail" -> [.tab(...), .open(search), ...]
@Test func searchComesFirstForSentences()       // "what is swift" with tab "Swift.org" -> first is .open(isSearch: true)
@Test func addressesOpenDirectly()              // "example.com" -> first .open(https://example.com, isSearch: false)
@Test func groupsAreCappedAndOrdered()          // 8 matching tabs, 4 commands, 4 archived, 7 history -> 1 open + 5 + 3 + 3 + 5 in that order
@Test func historyAlreadyOpenIsDropped()
@Test func emptyQueryShowsRecentTabs()          // 8 tabs with dates -> 6 newest, no .open

// CommandBarModelTests
@MainActor @Test func currentTabModeStartsWithAddress()
@MainActor @Test func typingResetsSelection()
@MainActor @Test func selectionIsClamped()      // moveSelection(-1) at 0 stays 0; past end stays last
@MainActor @Test func activateMapsResults()     // .open in newTab mode -> inNewTab true; in currentTab -> false; .tab -> .selectTab; .command -> .runCommand(id); .archived -> .restoreArchived(id); .history -> .open(url, inNewTab: true in newTab mode)
@MainActor @Test func activateWithNoResultsIsNil()
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter CommandBarTests`
Expected: build fails.

- [ ] **Step 4: Implement**

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter CommandBarTests`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add command bar ranking and model"
```

---

### Task 5: Command bar panel

**Files:**
- Create: `app/Packages/Sources/CommandBar/CommandBarViewController.swift`
- Create: `app/Packages/Sources/CommandBar/CommandBarRowView.swift`
- Test: `app/Packages/Tests/CommandBarTests/CommandBarViewControllerTests.swift`

**Interfaces:**
- Consumes: Task 4.
- Produces: `@MainActor public final class CommandBarViewController: NSViewController` with:
  - `init(model: CommandBarModel, icon: @escaping @MainActor (CommandBarResult) -> NSImage?, onAction: @escaping (CommandBarAction) -> Void, onDismiss: @escaping () -> Void)`
  - `func focus()`, which puts the cursor in the field with its text selected.

Layout:

- A rounded panel, 640 points wide, with `.popover` material, corner radius 14 and a shadow. A 48-point search field sits above a results table with 40-point rows, showing at most 8 rows before it scrolls.
- **Row text:**
  - `.open`: "Search Google for “<query>”" for searches, otherwise "Open <host><path>".
  - `.tab`: the title, with "Switch to Tab" on the right.
  - `.command`: the title.
  - `.archived`: the title, with "Restore" on the right.
  - `.history`: the title, with the host on the right.
- **Keyboard.** The field's delegate handles `moveUp:`, `moveDown:`, `insertNewline:` (activate the selected row) and `cancelOperation:` (dismiss). Clicking a row activates it.
- **Dismissing.** Owning and dismissing the panel is the app's job. This controller only calls `onAction` and `onDismiss`.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Test func showsOneRowPerResult()
@MainActor @Test func downArrowMovesSelection()     // send moveDown: through the field delegate -> model.selectedIndex 1, table selectedRow 1
@MainActor @Test func returnActivatesSelection()    // insertNewline: -> onAction called with the first result's action
@MainActor @Test func escapeDismisses()             // cancelOperation: -> onDismiss called, onAction not called
@MainActor @Test func typingUpdatesRows()           // set field text + controlTextDidChange -> rows match new results
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter CommandBarViewControllerTests`
Expected: build fails.

- [ ] **Step 3: Build the panel**

It updates through `keepObserving`. `CommandBar` gains a dependency on `SidebarUI` for it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add app/Packages
git commit -m "Add command bar panel"
```

---

### Task 6: The app

**Files:**
- Modify: `app/Brow.xcodeproj/project.pbxproj` (link `Archive`, `History`, `CommandBar`)
- Modify: `app/Brow/AppDelegate.swift`, `app/Brow/BrowserWindowController.swift`, `app/Brow/BrowserRootViewController.swift`, `app/Brow/MainMenu.swift`
- Create: `app/Brow/CommandBarPresenter.swift`
- Create: `app/Brow/ArchiveSweeper.swift`
- Modify: `app/Packages/Sources/SidebarUI/SidebarViewController.swift` (`var onAddressClicked: (() -> Void)?`; when set, a click on the address pill calls it instead of editing in place)
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.

The app has no unit tests. It's verified by a clean build and the hands-on checklist.

- [ ] **Step 1: Write the app code**

- **`AppDelegate`** creates one `ArchiveStore` and one `HistoryStore`. If the history database can't open, Brow runs without history instead of failing.
  - It passes the archive store to every window model, and sets each model's `onPageVisited` to `history.recordVisit`.
  - `ArchiveSweeper` runs `archiveInactiveTabs` at launch, every 5 minutes, and on `NSWorkspace.didWakeNotification`. It protects the selected item of every window and reads the interval from `ArchiveAfterHours`, where a missing value means 12.
- **`CommandBarPresenter`**, one per window, shows the panel as an overlay centred near the top of the content card, 120 points down, over a dimmed backdrop. A click on the backdrop dismisses it.
  - The sources are:
    - Tabs: every tab in favourites and every space. The title follows the sidebar's rule, the URL is the live or saved one, and `lastActiveAt` comes from `TabInfo`.
    - Commands: the list below.
    - Archived: `archive.search`.
    - History: `history.search(query, limit: 20)`.
  - Icons are favicons for tabs, archived and history rows. Commands get `command`, and `.open` gets `magnifyingglass` for a search or `globe` otherwise.
  - Actions: `.open` calls `model.newTab(url:)` or `model.load`, `.selectTab` calls `model.select`, `.restoreArchived` calls `model.restore`, and `.runCommand` runs the matching command.
- **Commands** (id: title):
  - `new-space`: New Space
  - `toggle-sidebar`: Toggle Sidebar
  - `copy-url`: Copy URL
  - `pin-tab`: Pin or Unpin Tab
  - `clear-unpinned`: Clear Unpinned Tabs
  - `reopen-archived`: Reopen Last Archived Tab
  - `clear-history`: Clear History…, which confirms with an alert first
  - `new-window`: New Window
- **Menus.**
  - File > New Tab (Cmd+T) and Open Location (Cmd+L) open the command bar in `.newTab` and `.currentTab` modes.
  - Tab menu adds Reopen Archived Tab (Cmd+Shift+T) and an "Archive Unpinned Tabs After" submenu: 12 Hours, 24 Hours, 7 Days, 30 Days, Never. The current choice is checked.
  - Clicking the sidebar's address opens the command bar in `.currentTab` mode.

- [ ] **Step 2: Build**

Run: `xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode build`
Expected: `** BUILD SUCCEEDED **` with no warnings from Brow's own files.

- [ ] **Step 3: Check it by hand**

1. Cmd+T, type part of an open tab's title, press Return. Brow switches to that tab.
2. Cmd+T, type `what is swift`, press Return. A new tab opens with Google results.
3. Cmd+L shows the current address selected. Typing a new one loads in the same tab.
4. Cmd+W on an unpinned tab, then Cmd+Shift+T, brings it back at the top of unpinned.
5. Set "Archive Unpinned Tabs After" to 12 Hours, and set your Mac's clock forward a day (or wait). Unpinned tabs you aren't looking at move to the archive and can be found from the command bar.

- [ ] **Step 4: Update the README**

Add `Archive`, `History` and `CommandBar` to the module list.

- [ ] **Step 5: Commit**

```bash
git add app README.md
git commit -m "Add the command bar and tab archiving to Brow"
```
