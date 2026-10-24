# Arc history import and settings implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** Brow brings in your Arc browsing history, and has a Settings window (Cmd+,) for the choices that are scattered through menus today.

**Architecture:**
- **Reading Arc's history:** `ArcImport` reads the `urls` table of Arc's Chromium `History` database, opened read-only and immutable so a running Arc isn't disturbed.
- **Merging it:** `HistoryStore` gains an import that merges those visits without double-counting.
- **The Settings window:** a SwiftUI form hosted in an `NSWindowController`, over state the packages already own. `SitePermissions` and `ContentBlocker` gain the small listing APIs the window needs.

**Tech stack:** Swift 6, SwiftPM, Swift Testing, SQLite3, AppKit with SwiftUI hosted inside it.

**Spec:** `docs/design/2026-10-23-brow-design.md`, "Import from Arc" (history) and milestone 6 ("settings").

## Global constraints

- Everything from earlier plans applies:
  - No AI tool mentions.
  - No WebKit import outside `WebKitEngine`.
  - `xcodebuild` uses `-skipPackagePluginValidation`.
- Arc's history lives at `<Arc root>/User Data/Default/History`, plus `User Data/Profile N/History` for any other profiles.
  - Open each one with the URI `file:<path>?immutable=1`, read-only.
  - `last_visit_time` counts microseconds since 1601-01-01: Unix seconds = `t / 1_000_000 - 11_644_473_600`.
  - Only `http` and `https` rows with `hidden = 0`, from the last 90 days, come across, which matches History's retention.
- An imported row merges with what Brow already has for that address. The visit count becomes the larger of the two, the last visit becomes the later of the two, and the title stays unless Brow has none.
- **When the import runs:**
  - Once on first launch, after the sidebar offer, whatever you chose for the sidebar.
  - Again from File > "Import History from Arc…" or Settings.
  - It never runs twice by itself: `UserDefaults` key `ArcHistoryImported` records it.
- **The Settings window has four sections:**
  - General:
    - make Brow the default browser
    - sleep tabs after
    - archive after
  - Ad blocking:
    - on/off
    - the sites where it's off, each with a remove button
  - Permissions: the sites with camera or microphone choices, each with a forget button
  - Import:
    - "Import History from Arc"
    - "Import Sidebar from Arc", which is disabled once a sidebar exists, because it would replace yours

## Review focus

1. **Arc running while importing.** Reading never fails because Arc is open, and never writes to Arc's files. (Task 1)
2. **Importing twice.** Visit counts don't double. (Task 2)
3. **Arc not installed, or no History file.** Import reports zero pages and nothing breaks. (Task 1)
4. **A history row with no title or a strange address** (`chrome://`, `file:`, `javascript:`). It's skipped, or kept without a title. (Task 1)
5. **Turning ad blocking back on for a site from Settings.** It takes effect on that site's next page load. (Task 3)

---

### Task 1: Read Arc's history

**Files:**
- Create: `app/Packages/Sources/ArcImport/ArcHistoryReader.swift`
- Modify: `app/Packages/Sources/ArcImport/ArcDataLocation.swift`, which gains `historyFileURLs: [URL]`, and `app/Packages/Package.swift`, where `ArcImport` links `sqlite3`
- Test: `app/Packages/Tests/ArcImportTests/ArcHistoryReaderTests.swift`

**Interfaces:**
- Produces:
  - `public struct ArcHistoryVisit: Equatable, Sendable { public let url: URL; public let title: String?; public let visitCount: Int; public let lastVisitedAt: Date }`
  - `public func readArcHistory(from location: ArcDataLocation, since cutoff: Date) -> [ArcHistoryVisit]` reads every profile's `History`. Files that are missing or can't be read are skipped. Visits are newest first.
  - `ArcDataLocation.historyFileURLs` lists `Default` and every `Profile *` folder that has a `History` file.

- [ ] **Step 1: Failing tests**

The tests build a Chromium-shaped database with `sqlite3`: the `urls` table exactly as Arc has it, in a temporary folder laid out as `User Data/Default/History` and `User Data/Profile 1/History`.
- `readsVisitsNewestFirst`: two rows convert to the right Unix dates and titles.
- `skipsHiddenOldAndNonWebRows`: rows that are hidden, older than the cutoff, or `chrome://`, `file:` or `javascript:` addresses are left out.
- `emptyTitlesBecomeNil`
- `readsEveryProfile`
- `missingArcGivesNothing`: a folder with no `User Data` gives `[]`.

- [ ] **Step 2: See them fail, implement, see them pass, commit**

Run: `swift test --filter ArcHistoryReaderTests`
Expected: fail, then pass after implementing.

```bash
git commit -am "Read browsing history from Arc"
```

---

### Task 2: Merge it into History

**Files:**
- Modify: `app/Packages/Sources/History/HistoryStore.swift`
- Test: `app/Packages/Tests/HistoryTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces: `public func importVisits(_ visits: [HistoryEntry]) -> Int` returns how many rows were added or changed. It runs in one transaction.

- [ ] **Step 1: Failing tests**
- `importAddsNewPages`
- `importTwiceDoesNotDoubleCounts`: importing the same visits twice leaves `visitCount` at the imported value.
- `importKeepsTheLaterVisitAndLargerCount`: Brow's own newer visit and larger count win over an older import.
- `importKeepsExistingTitles`

- [ ] **Step 2: See them fail, implement with `INSERT … ON CONFLICT(url) DO UPDATE SET visit_count = max(…), last_visited = max(…), title = COALESCE(visits.title, excluded.title)`, see them pass, commit**

Run: `swift test --filter HistoryStoreTests`
Expected: fail, then pass.

```bash
git commit -am "Merge imported visits into history"
```

---

### Task 3: Listing APIs for Settings

**Files:**
- Modify: `app/Packages/Sources/Browsing/SitePermissions.swift`, `app/Packages/Sources/ContentBlocking/ContentBlocker.swift`
- Test: `SitePermissionsTests.swift`, `ContentBlockerTests.swift`

**Interfaces:**
- Produces:
  - `SitePermissions.sites() -> [(site: String, camera: Bool?, microphone: Bool?)]`, sorted by site
  - `SitePermissions.forget(site: String)`
  - `ContentBlocker.setBlocking(_ on: Bool, forSite site: String)`

- [ ] **Step 1: Failing tests**
- `sitesListsEveryChoice`
- `forgetBySiteName`
- `turningASiteBackOnByName`: after `setBlocking(true, forSite: "example.com")`, `isBlocking(on: https://shop.example.com/)` is true.

- [ ] **Step 2: See them fail, implement, see them pass, commit**

Run: `swift test --filter "SitePermissionsTests|ContentBlockerTests"`
Expected: fail, then pass.

```bash
git commit -am "Let settings list and change site choices"
```

---

### Task 4: The Settings window and the import command

**Files:**
- Create: `app/Brow/SettingsWindowController.swift` (an `NSWindowController` with an `NSHostingController` around a SwiftUI `Form` in a `TabView` with General, Ad Blocking, Permissions and Import)
- Create: `app/Brow/HistoryImport.swift`
- Modify: `app/Brow/AppDelegate.swift`, `MainMenu.swift`, `FirstRunImport.swift`, `README.md`

- [ ] **Step 1: Build it (no app-target tests)**
- **Menus:** Brow > "Settings…" (Cmd+,) opens the window, reusing one instance. File > "Import History from Arc…" runs `HistoryImport`.
- **`HistoryImport.run(into:)`:**
  - Reads with `readArcHistory(from: .live, since: now - 90 days)` and converts to `HistoryEntry`.
  - Calls `importVisits` and sets `ArcHistoryImported`.
  - Shows "Imported N pages from Arc", or "Arc has no history to import" when there's nothing.
- **First launch:** after `FirstRunImport.document()`, run the import once without an alert, if `ArcHistoryImported` isn't set and Arc's history exists.
- **Default browser:** the button calls `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")`, then again for `https`. It shows "Brow is your default browser" once `NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)` points at Brow.
- **Menus stay:** the existing archive and sleep submenus stay in their menus. Settings uses the same keys.

- [ ] **Step 2: Run the suite and build, then commit**

Run: `swift test` and the Debug `xcodebuild`.
Expected: all tests pass and `BUILD SUCCEEDED`.

```bash
git commit -am "Add a Settings window and import history from Arc"
```
