# Split view and Peek implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** Two to four tabs show side by side in one window as a split view that lives in the sidebar as one row, and links from pinned tabs and favourites to other sites open in Peek, a floating preview over the page that can become a tab or a split.

**Architecture:**
- A split is a new sidebar item kind whose children are its tabs. Selection stays a tab, the focused pane. The window shows the whole split whenever the selected tab is inside one.
- `BrowserWindowModel` owns the split operations and the one Peek per window. Engines ask the model before following a link, so the model can send the link to Peek instead.
- The app draws panes as separate cards and Peek as an overlay. Pane geometry is a pure function in `Browsing` so it can be tested.

**Tech stack:** Swift 6 language mode, SwiftPM, Swift Testing, AppKit, Observation, WebKit (only inside `WebKitEngine`). No third-party dependencies.

**Spec:** `docs/design/2026-10-23-brow-design.md`, the "Split view" and "Peek" goals and milestone 5.

## Global constraints

- Everything from the earlier plans still applies:
  - macOS 15 floor, tools version 6.0.
  - No AI tool mentions anywhere in the repository. Plain imperative commit subjects with no attribution lines.
  - No Arc assets, no telemetry.
  - No WebKit import outside `WebKitEngine`.
- A split holds 2 to 4 tabs. It can live anywhere a tab can, except favourites. A favourite can't join a split.
- A split's panes start at equal sizes. A pane is never narrower or shorter than 240 pt, and the gap between panes is 8 pt.
- Shortcuts follow Arc:
  - Ctrl+Shift+= adds a split pane.
  - Ctrl+Shift+- separates the split.
  - Escape or Cmd+W closes Peek.
- The sidebar file goes to version 2. Version 1 files still load. A version 2 file in an older Brow opens read-only, which the store already handles.
- Peek opens for a plain left-click link from a pinned tab or favourite to a different site, and for a Shift-click link from any tab. Cmd-clicks and middle-clicks keep opening background tabs.
- Arc's split view items stay unsupported by the importer. The owner's Arc data has none.

## Review focus

1. **Closing panes one by one.** When one pane is left, the split row disappears and the last tab takes its place in the sidebar, still selected. (Tasks 1 and 3)
2. **Archiving a split with one pane in use.** No pane of that split is archived until every pane is overdue. (Task 2)
3. **Same-site links in pinned tabs.** `mail.google.com` to `calendar.google.com`, and `www.fnb.co.za` to `online.fnb.co.za`, stay in the tab instead of opening Peek. (Task 6)
4. **Selecting a split restored from disk.** Every pane loads, not only the focused one. (Task 3)
5. **Leaving Peek open.** Switching space, selecting another tab or closing the window closes the Peek page, so it doesn't keep playing audio. (Task 7)

---

### Task 1: Split items in the sidebar document

**Files:**
- Modify: `app/Packages/Sources/SidebarModel/SidebarItem.swift`, `SidebarDocument.swift` (`currentVersion = 2`), `SidebarDocument+Editing.swift`, `SidebarDocument+Queries.swift`, `SidebarError.swift`
- Create: `app/Packages/Sources/SidebarModel/SidebarDocument+Splits.swift`
- Modify: `app/Packages/Sources/Sidebar/SidebarStore+Editing.swift`
- Test: `app/Packages/Tests/SidebarModelTests/SidebarSplitsTests.swift`

**Interfaces:**
- Produces:
  - `SidebarItem.Kind.split(SplitInfo)`
  - `public struct SplitInfo: Codable, Equatable, Sendable { public var orientation: SplitOrientation; public var fractions: [Double] }`
  - `public enum SplitOrientation: String, Codable, Sendable { case horizontal, vertical }`. Horizontal means side by side.
  - `SidebarError.notAllowedInSplit(ItemID)` and `SidebarError.splitFull(ItemID)`
  - `SidebarDocument`:
    - `mutating func addToSplit(_ id: ItemID, with anchor: ItemID) throws -> ItemID`. This puts `id` right after `anchor`. If `anchor` isn't in a split yet, it makes a new horizontal split in the anchor's place. It returns the split's ID and resets fractions to equal.
    - `mutating func separate(_ splitID: ItemID) throws`. The split's tabs take its place, in order.
    - `mutating func setSplitFractions(_ splitID: ItemID, _ fractions: [Double]) throws`
    - `mutating func setSplitOrientation(_ splitID: ItemID, _ orientation: SplitOrientation) throws`
    - `func splitID(containing tabID: ItemID) -> ItemID?`
  - `SidebarStore`:
    - `@discardableResult func addToSplit(_ id: ItemID, with anchor: ItemID) -> ItemID?`
    - `func separateSplit(_ id: ItemID)`
    - `func setSplitFractions(_ id: ItemID, _ fractions: [Double])`
    - `func setSplitOrientation(_ id: ItemID, _ orientation: SplitOrientation)`

- [ ] **Step 1: Write the failing tests**

Build each test from `fixtureDocument()`. Names and assertions:
- `addingMakesASplitInTheAnchorsPlace`
  - Do: `addToSplit("u2", with: "u1")` returns `s`.
  - Expect:
    - `U` children are `[s]` and `s` children are `["u1", "u2"]`.
    - Its kind is `.split(SplitInfo(orientation: .horizontal, fractions: [0.5, 0.5]))`.
- `addingToASplitGoesAfterTheAnchorAndEvensSizes`
  - Do: put `p1` into the split from the previous test with anchor `u1`.
  - Expect: children `["u1", "p1", "u2"]` and every fraction `1.0 / 3`.
- `aFifthPaneIsRefused`
  - Do: fill a split to 4 panes, then add a fifth tab.
  - Expect: it throws `.splitFull`.
- `favouritesCantJoinSplits`
  - Do: `addToSplit("f1", with: "u1")` and `addToSplit("u1", with: "f1")`.
  - Expect: both throw `.notAllowedInSplit`.
- `foldersCantJoinSplits`
  - Do: `addToSplit("fold", with: "u1")`.
  - Expect: it throws `.notAllowedInSplit`.
- `removingDownToOnePaneDissolvesTheSplit`
  - Do: make split `s` of `u1`, `u2` in `U`, then `remove("u1")`.
  - Expect:
    - `U` children are `["u2"]`, `u2.parentID == "U"` and `s` no longer exists.
    - `validate()` passes.
- `movingAPaneOutDissolvesTheSplit`
  - Do: make the same split, then `move("u2", to: "P", at: 0)`.
  - Expect: `U` children `["u1"]`, `P` children start with `u2`, and `s` is gone.
- `separatingPutsTabsInPlace`
  - Do: make the split, then `separate(s)`.
  - Expect: `U` children `["u1", "u2"]`.
- `splitsCantGoInFavourites`
  - Do: `move(s, to: "F", at: nil)`.
  - Expect: it throws.
- `validateRejectsBadSplits`
  - Expect: `validate()` throws for:
    - a split with one child
    - a split with a folder child
    - fractions whose count differs from the child count
- `versionOneFilesStillLoad`
  - Do: save a document with `version: 1` through `SidebarDocumentStore`, then load it.
  - Expect: it loads with no error.
- `splitsSurviveSaveAndLoad`
  - Expect: a round trip through `SidebarDocumentStore` keeps the split's kind and children.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter SidebarSplitsTests` from `app/Packages`
Expected: compile errors for `addToSplit` and `.split`.

- [ ] **Step 3: Implement**

Each step has a code location and a rule:
- **`canHaveChildren`:** true for `.split`.
- **`insert` and `move` into a split:** go through the same checks, so only non-favourite tabs and at most 4 panes are allowed.
- **`remove` and `move` of a pane:** after either one, call a private `collapseSplitIfNeeded(_ splitID: ItemID)`. With one child left, the child replaces the split at its index in the split's parent. With none left, the split is removed. With 2 or more left, fractions reset to equal.
- **`validate`:** checks 2 to 4 tab children and matching fractions, and that no split is in favourites.
- **`tabIDs(under:)`:** already reaches split children. Confirm it with a test, without changing it.
- **Store wrappers:** go through `change`, like the other edits.
- **Every switch over `SidebarItem.Kind`:** must handle `.split`, including in `SidebarUI` and `ArcImport`. A split shows the title "Split View" anywhere a folder name would show.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "Add split view items to the sidebar document"
```

---

### Task 2: Splits in the outline and the archive

**Files:**
- Modify: `app/Packages/Sources/Sidebar/OutlineRows.swift`, `app/Packages/Sources/Archive/InactiveTabs.swift`
- Test: `app/Packages/Tests/SidebarTests/OutlineRowsTests.swift`, `app/Packages/Tests/ArchiveTests/InactiveTabsTests.swift`

**Interfaces:**
- Consumes: Task 1's `.split` kind and `addToSplit`.
- Produces: no new API. A split is one outline row, and a split archives as a unit.

- [ ] **Step 1: Write the failing tests**

- `aSplitIsOneRow`
  - Do: put `u1` and `u2` in a split `s`.
  - Expect:
    - `outlineSnapshot` for space `S` lists `.item(s)` and no `.item("u1")` or `.item("u2")`.
    - `childRows(of: s)` is empty.
- `nothingDropsIntoASplit`
  - Expect: `dropDestination(parent: .item(s), childIndex: 0, …)` is nil.
- `aSplitArchivesOnlyWhenEveryPaneIsDue`
  - Setup: split `u1` (active 13 hours ago) with `u2` (active 1 hour ago).
  - Expect:
    - `inactiveTabs(… after: 12 hours …)` is empty.
    - With both 13 hours old, it returns `["u1", "u2"]`.
- `aProtectedPaneProtectsItsSplit`
  - Do: make both panes overdue, with `protecting: ["u2"]`.
  - Expect: an empty result.
- `archivingASplitRemovesIt`
  - Do: run `archiveInactiveTabs` on an overdue split.
  - Expect: two archive entries, and neither the split nor its tabs left in the sidebar.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter "OutlineRowsTests|InactiveTabsTests"`
Expected: `aSplitIsOneRow` and the archive tests fail.

- [ ] **Step 3: Implement**

- `childRows(of:)` returns `[]` for a split.
- `dropDestination` returns nil for a split row.
- `inactiveTabs` walks the unpinned container's top-level children. A split counts as due only when all its panes are due and none is protected, and then contributes all its pane IDs.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "Show a split as one sidebar row and archive it as a unit"
```

---

### Task 3: Split operations in the window model

**Files:**
- Modify: `app/Packages/Sources/Browsing/BrowserWindowModel.swift`
- Create: `app/Packages/Sources/Browsing/SplitLayout.swift`
- Test: `app/Packages/Tests/BrowsingTests/BrowserWindowSplitTests.swift`

**Interfaces:**
- Consumes: Task 1's store methods.
- Produces:
  - `public struct SplitLayout: Equatable { public let id: ItemID; public let paneIDs: [ItemID]; public let orientation: SplitOrientation; public let fractions: [Double] }`
  - On `BrowserWindowModel`:
    - `public var selectedSplit: SplitLayout?`. This is the split holding the selected tab, or nil.
    - `@discardableResult public func addSplitPane() -> ItemID?`. This adds a blank tab after the selected tab and selects it. It returns nil with no selection, a favourite selected, or a full split.
    - `public func openInSplit(_ id: ItemID)`. This adds an existing tab after the selected one and selects it.
    - `public func separateSelectedSplit()`, `public func rotateSelectedSplit()` and `public func resizeSelectedSplit(_ fractions: [Double])`
    - `public func closeSplit(_ splitID: ItemID)`
    - `select(_:)` now also accepts a split's ID and selects its pane with the latest `lastActiveAt`, or its first pane.

- [ ] **Step 1: Write the failing tests**

Use the `Harness` pattern from `BrowserWindowArchiveTests.swift`.
- `addSplitPaneMakesASplitWithANewBlankTab`
  - Do: select `u1`, then `addSplitPane()` returns `n`.
  - Expect:
    - `selectedItemID == n`.
    - `selectedSplit?.paneIDs == ["u1", n]`.
    - `live(n)?.loadedURLs == []`.
- `addSplitPaneRefusesFavourites`
  - Do: select `f1`.
  - Expect: `addSplitPane()` is nil and the document is unchanged.
- `selectingASplitLoadsEveryPane`
  - Do: build a split of `p1` and `u1` in the store before the model exists, then `select(splitID)`.
  - Expect: both `live("p1")` and `live("u1")` exist.
- `selectingTheSplitRowPicksTheLastUsedPane`
  - Do: select `u1`, then `u2`, then `openInSplit("u1")`, then select `p1`, then `select(splitID)`.
  - Expect: `selectedItemID == "u1"`.
- `closingAPaneSelectsItsNeighbour`
  - Do: in a split of `u1`, `u2`, `p1` with `u2` focused, `close("u2")`.
  - Expect: `selectedItemID == "p1"`, and `selectedSplit?.paneIDs == ["u1", "p1"]`.
- `closingTheSecondLastPaneLeavesAPlainTab`
  - Do: in a split of `u1`, `u2`, `close("u2")`.
  - Expect: `selectedSplit == nil`, `selectedItemID == "u1"`, and `U` children start with `u1`.
- `closeSplitArchivesUnpinnedPanes`
  - Do: `closeSplit(s)` on a split of `u1`, `u2`.
  - Expect: 2 archive entries, and both tabs are gone.
- `rotateAndResize`
  - Do: rotate, then `resizeSelectedSplit([0.3, 0.7])`.
  - Expect: `selectedSplit?.orientation == .vertical` and `fractions == [0.3, 0.7]`.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter BrowserWindowSplitTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

- **`setSelection`:** when the target is inside a split, register a live tab for every pane that has none, using its saved URL.
- **Selection after closing a pane:** the next pane, otherwise the previous pane, otherwise the existing rules.
- **`closeSplit`:** goes through `close` for each pane, so the archive rules stay in one place.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "Add split view to the window model"
```

---

### Task 4: Pane geometry and the split content view

**Files:**
- Create: `app/Packages/Sources/Browsing/SplitGeometry.swift`
- Test: `app/Packages/Tests/BrowsingTests/SplitGeometryTests.swift`
- Modify: `app/Brow/WebContentViewController.swift`, `app/Brow/BrowserRootViewController.swift`
- Create: `app/Brow/PageCardView.swift`

**Interfaces:**
- Consumes: `selectedSplit` and `resizeSelectedSplit` from Task 3.
- Produces:
  - `public func paneFrames(in bounds: CGRect, orientation: SplitOrientation, fractions: [Double], gap: CGFloat) -> [CGRect]`
  - `public func fractions(afterDragging divider: Int, to position: CGFloat, in bounds: CGRect, orientation: SplitOrientation, fractions: [Double], gap: CGFloat, minimum: CGFloat) -> [Double]`. Here `position` is the divider's new centre along the split axis. Only the two panes beside the divider change.

- [ ] **Step 1: Write the failing geometry tests**

- `twoEqualPanesSideBySide`
  - Input: bounds `0,0,1008,600`, horizontal, `[0.5, 0.5]`, gap 8.
  - Expect: `[0,0,500,600]` and `[508,0,500,600]`.
- `verticalStacksTopToBottomInFlippedSpace`
  - Input: bounds `0,0,800,1008`, vertical, `[0.5, 0.5]`.
  - Expect: `[0,0,800,500]` and `[0,508,800,500]`.
- `draggingMovesOnlyTheNeighbours`
  - Input: three equal panes in 1016 wide, dragging divider 0 to x 300.
  - Expect: a result that sums to 1, an unchanged third fraction, and a first pane 296 wide.
- `draggingStopsAtTheMinimum`
  - Do: drag divider 0 to x 10 with minimum 240.
  - Expect: a first pane 240 wide.

- [ ] **Step 2: Run them and see them fail, implement, see them pass**

Run: `swift test --filter SplitGeometryTests`
Expected: fail before, pass after. Frames round to whole points, and the last pane takes any remainder.

- [ ] **Step 3: Draw the panes**

These pieces have no app-target tests:
- **Card styling:** move the card look (10 pt corner radius, clipping, window background, the soft shadow) from `BrowserRootViewController` into `PageCardView`. The root's card becomes a plain container.
- **Layout:** `WebContentViewController` shows one `PageCardView` per pane of `model.selectedSplit`, or one card for the selected tab. Frames come from `paneFrames` with gap 8, laid out in `viewDidLayout`.
- **Focus outline:** with 2 or more panes, the focused pane's card gets a 2 pt inner border in `controlAccentColor` at 0.6 alpha. The others get none.
- **Click to focus:** a local `leftMouseDown` monitor, active while the view is in a key window, calls `model.select(paneID)` for the pane under the click. It always passes the event on.
- **Dividers:** the 8 pt gaps between panes show the resize cursor. Dragging one calls `model.resizeSelectedSplit(fractions(afterDragging:…, minimum: 240))` live.
- **Focus moves with the pane:** keep the existing rule that the page keeps keyboard focus when it had it, applied to the focused pane.

- [ ] **Step 4: Build and check by eye**

Run: `xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode build`
Expected: `BUILD SUCCEEDED`, with no new warnings. Then try three things by hand:
1. Make a split with Ctrl+Shift+= after Task 5, or temporarily from a test document.
2. Drag the divider.
3. Click each pane.

- [ ] **Step 5: Commit**

```bash
git commit -am "Show split panes side by side as separate cards"
```

---

### Task 5: Split row, menus and commands

**Files:**
- Modify: `app/Packages/Sources/SidebarUI/SidebarCells.swift` (add `SplitCellView`), `SpacePageView.swift`
- Modify: `app/Brow/MainMenu.swift`, `app/Brow/BrowserWindowController.swift`, `app/Brow/CommandBarPresenter.swift`
- Test: `app/Packages/Tests/SidebarUITests/SidebarViewControllerTests.swift`

**Interfaces:**
- Consumes: Task 3's model methods.
- Produces:
  - `SplitCellView`, with up to 4 segments, each showing a favicon and a title.
  - The command IDs `add-split`, `separate-split` and `rotate-split`.

- [ ] **Step 1: Write the failing sidebar tests**

- `aSplitShowsOneRowWithASegmentPerPane`
  - Do: make a split of `u1`, `u2`.
  - Expect: the page's outline has a `SplitCellView` with 2 segments titled `"u1 title"` and `"u2 title"`.
- `clickingASegmentSelectsThatPane`
  - Do: call the segment's click handler for index 1.
  - Expect: `model.selectedItemID == "u2"`.
- `tabMenuOffersOpenInSplitView`
  - Do: right-click `u1` while `u2` is selected.
  - Expect: the menu has an enabled "Open in Split View" item. It's disabled when the clicked tab is selected or either tab is a favourite.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter SidebarUITests`
Expected: the new tests fail.

- [ ] **Step 3: Implement**

- **Split row:**
  - The row is 32 pt high. Segments split the width evenly, with 1 pt separators in `separatorColor`.
  - The selected row highlights as usual, and the focused pane's segment title uses `labelColor` while the others use `secondaryLabelColor`.
  - Hovering shows the close button, which calls `closeSplit`.
- **Context menus:**
  - A split row gets "Separate Split View" and "Close Split View".
  - A tab row gets "Open in Split View", which calls `model.openInSplit(id)`.
- **Tab menu items:**
  - "Add Split View" (Ctrl+Shift+=) calls `addSplitPane()`, then `commandBar.show(.currentTab(address: ""))`.
  - "Separate Split View" (Ctrl+Shift+-).
  - "Rotate Split View", with no shortcut.
  - Validate all three: Add needs a non-favourite selection and fewer than 4 panes, and the other two need `selectedSplit`.
- **Command bar commands:**
  - `add-split`: "Add Split View", keywords `["side", "pane"]`
  - `separate-split`: "Separate Split View", keywords `["unsplit"]`
  - `rotate-split`: "Rotate Split View", keywords `["vertical", "horizontal"]`

- [ ] **Step 4: Run the suite and build**

Run: `swift test` and the `xcodebuild` command from Task 4.
Expected: all tests pass and `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git commit -am "Add split view rows, menus and commands"
```

---

### Task 6: Links can go to Peek

**Files:**
- Modify: `app/Packages/Sources/BrowserEngine/BrowserTabDelegate.swift`, `app/Packages/Sources/WebKitEngine/WebKitTab.swift`, `app/Packages/Sources/FakeEngine/FakeTab.swift`
- Create: `app/Packages/Sources/Browsing/SiteKey.swift`
- Test: `app/Packages/Tests/BrowsingTests/SiteKeyTests.swift`, `app/Packages/Tests/FakeEngineTests/FakeTabTests.swift`

**Interfaces:**
- Produces:
  - `BrowserTabDelegate.tab(_ tab: any BrowserTab, shouldFollowLinkTo url: URL, shiftKey: Bool) -> Bool`. A protocol extension returns `true` by default. `false` means the delegate opened the link somewhere else, so the tab cancels the navigation.
  - `FakeTab.simulateLinkClick(to url: URL, shiftKey: Bool = false)`. This asks the delegate and calls `load(url)` when it returns true.
  - `public func siteKey(forHost host: String) -> String`

- [ ] **Step 1: Write the failing tests**

- `siteKeys`, with each input expected to give the output shown:

| Input | `siteKey` |
| --- | --- |
| `mail.google.com` | `google.com` |
| `www.fnb.co.za` | `fnb.co.za` |
| `online.fnb.co.za` | `fnb.co.za` |
| `bbc.co.uk` | `bbc.co.uk` |
| `news.bbc.co.uk` | `bbc.co.uk` |
| `localhost` | `localhost` |
| `192.168.1.10` | `192.168.1.10` |
| `GitHub.COM` | `github.com` |

- `linkClickAsksTheDelegate`
  - Do: use a delegate returning false.
  - Expect: `simulateLinkClick` leaves `loadedURLs` unchanged. With true, the URL loads.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter "SiteKeyTests|FakeTabTests"`
Expected: compile errors.

- [ ] **Step 3: Implement**

- **`siteKey`:** lowercase the host, then:
  - IP addresses and single-label hosts return as they are.
  - Otherwise keep the last 2 labels, or the last 3 when the last label is 2 letters and the second-last is 3 letters or fewer, such as `co.za`, `org.za` or `co.uk`.
- **`WebKitTab`:** in `decidePolicyFor navigationAction`, ask the delegate only when all of these hold:
  - the navigation type is `.linkActivated`
  - the target is the main frame
  - `newTabDisposition(modifiers:buttonNumber:)` is nil
  - the URL scheme is http or https

  Cancel the navigation when the delegate returns false.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "Let the window decide where a clicked link opens"
```

---

### Task 7: Peek in the window model

**Files:**
- Modify: `app/Packages/Sources/Browsing/BrowserWindowModel.swift`
- Test: `app/Packages/Tests/BrowsingTests/BrowserWindowPeekTests.swift`

**Interfaces:**
- Consumes: `shouldFollowLinkTo` and `siteKey` from Task 6, and `openInSplit` from Task 3.
- Produces on `BrowserWindowModel`:
  - `public private(set) var peekTab: (any BrowserTab)?`
  - `public func closePeek()`
  - `@discardableResult public func expandPeek() -> ItemID?`. This makes a new unpinned tab at the top of the current space from the live Peek page, without reloading it, and selects it.
  - `public func splitPeek()`. This expands, then puts the new tab in a split with the tab that was selected. When that tab is a favourite, it only expands.
  - `public var canSplitPeek: Bool`

- [ ] **Step 1: Write the failing tests**

Use the FakeEngine harness throughout.
- `pinnedTabLinkToAnotherSiteOpensPeek`
  - Do: select `p1`, then `live("p1")!.simulateLinkClick(to: https://other.example.org/)`.
  - Expect: `peekTab?.loadedURLs == [that URL]`, `p1` loaded nothing new, and the sidebar is unchanged.
- `pinnedTabLinkOnTheSameSiteStaysInTheTab`
  - Do: in `p1` (at `https://p1.example.com/`), click to `https://other.example.com/`.
  - Expect: `peekTab == nil`.
- `favouritesPeekToo`
  - Expect: the same as the first test, from `f1`.
- `unpinnedTabsOnlyPeekOnShiftClick`
  - Do: in `u1`, click a different site.
  - Expect: no Peek. With `shiftKey: true`, a Peek opens.
- `aSecondPeekReplacesTheFirst`
  - Expect: the first Peek tab `isClosed`.
- `expandKeepsTheLivePage`
  - Do: open a Peek, then `expandPeek()` returns `n`.
  - Expect:
    - `liveTab(for: n) === the former peek tab`.
    - `U` children start with `n`.
    - `selectedItemID == n` and `peekTab == nil`.
- `splitPeekSplitsWithTheSourceTab`
  - Do: from `p1`, run `splitPeek()`.
  - Expect: `selectedSplit?.paneIDs == ["p1", n]`.
- `leavingClosesPeek`
  - Do: open a Peek, then each of `select("u1")`, `selectSpace("S2")` and `closeAllLiveTabs()`, one at a time.
  - Expect: each closes the Peek tab (`isClosed`).
- `peekVisitsCountAsHistory`
  - Expect: `onPageVisited` is called when the Peek page finishes loading.
- `peekDialogsShowFirst`
  - Expect: while a Peek is open, `dialogForSelectedTab` returns the Peek page's dialog.
- `peekCanCloseItself`
  - Do: `peekTab.simulateRequestClose()`.
  - Expect: `peekTab == nil`.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter BrowserWindowPeekTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

- **Choosing Peek:** `shouldFollowLinkTo` opens Peek and returns false when either:
  - the source tab is in pinned or favourites (`containerRole` `.pinned` or `.favorites`) and the link's `siteKey` differs from the current page's, or
  - `shiftKey` is set.
- **The Peek tab:** its delegate is the model.
  - Its pages opening new tabs go to the sidebar as if opened by the source tab.
  - Its state changes record history.
  - Its close requests close the Peek.
- **When Peek closes:** `setSelection` and `selectSpace` close an open Peek before changing anything.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git commit -am "Open links from pinned tabs and favourites in Peek"
```

---

### Task 8: Peek overlay and README

**Files:**
- Create: `app/Brow/PeekPresenter.swift`
- Modify: `app/Brow/BrowserWindowController.swift`, `app/Brow/BrowserRootViewController.swift`, `README.md`

**Interfaces:**
- Consumes: `peekTab`, `closePeek`, `expandPeek`, `splitPeek` and `canSplitPeek` from Task 7. Also `PageCardView` from Task 4 and `HoverButton`, which needs to become `public` in `SidebarUI`.

- [ ] **Step 1: Build the overlay**

These pieces have no app-target tests:
- **Dimming:** `PeekPresenter` watches `model.peekTab` with `keepObserving`. While it's set, a backdrop over the page card area dims it with black at 0.25 alpha. Clicking the backdrop calls `closePeek()`.
- **The card:** a `PageCardView` holding `peekTab.contentView`, inset 48 pt from the left and right of the card area and 32 pt from the top and bottom. It uses the command bar's shadow (opacity 0.25, radius 24, y offset -8).
- **Buttons:** a column of `HoverButton`s outside the card's top right corner, on a small rounded material pill:
  - `rectangle.split.2x1`, "Open in Split View". Hidden when `!canSplitPeek`.
  - `arrow.up.left.and.arrow.down.right`, "Open as Tab".
  - `xmark`, "Close".
- **Animation:** the overlay fades in while the card settles 8 pt into place over 0.2 s, with the same curve as the command bar, and fades out over 0.12 s. With Reduce Motion on, it only fades.
- **Keyboard:** the Peek page gets keyboard focus when Peek opens. Escape closes Peek through a local key monitor active only while the Peek shows in the key window. Cmd+W (`closeTab`) closes the Peek first when one is open.

- [ ] **Step 2: Update the README**

In the "Brow is early" paragraph, add that it shows tabs side by side in split view, and that links from pinned tabs open in Peek.

- [ ] **Step 3: Run the suite, build and check by eye**

Run: `swift test` and the `xcodebuild` command.
Expected: all tests pass and `BUILD SUCCEEDED`. Then check by hand:
1. A pinned Gmail tab, a link to another site, shows Peek. Try Escape, expand and split.
2. A same-site link stays in the tab.
3. Shift-click in an unpinned tab shows Peek.

- [ ] **Step 4: Commit**

```bash
git commit -am "Show Peek over the page and add split view and Peek to the README"
```
