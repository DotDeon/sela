# Content blocking implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** Brow blocks ads and trackers on every page by default, using EasyList and EasyPrivacy converted by AdGuard's SafariConverterLib. Lists refresh daily, and you can turn blocking off globally or for one site.

**Architecture:**
- **`ContentBlocking` (new module):**
  - It downloads and keeps the filter lists.
  - It converts them with AdGuard's `ContentBlockerConverter`, which gives WebKit content rules plus a small set of "advanced" rules.
  - It answers which advanced rules apply to a page through AdGuard's `FilterEngine`.
  - Its `ContentBlocker` coordinator owns the settings and feeds everything to the engine.
- **The engine** gets an optional `ContentBlockingEngine` capability. `WebKitEngine` implements it in two parts:
  - compiled `WKContentRuleList`s, switched per page load
  - a bundled page script, AdGuard's `@adguard/safari-extension` content script, that applies the advanced rules in an isolated content world
- **Boundaries:** WebKit stays inside `WebKitEngine`, and AdGuard's Swift code stays inside `ContentBlocking`.

**Tech stack:** Swift 6 language mode, SwiftPM, Swift Testing, AppKit, WebKit (only in `WebKitEngine`), CryptoKit. Third-party code:
- `SafariConverterLib` 4.3.1 (Swift, GPL-3.0, with its dependencies `PunycodeSwift`, `swift-psl` and `swift-argument-parser`)
- `@adguard/safari-extension` 4.3.1, `@adguard/extended-css` and `@adguard/scriptlets` (JavaScript, GPL-3.0), bundled with esbuild into one committed file

**Spec:** `docs/design/2026-10-23-brow-design.md`. Content blocking isn't in the design yet. The owner chose it on 2026-10-23, along with AdGuard's library and GPL-3.0 for Brow. Task 1 adds it to the design's Decisions.

## Global constraints

- Everything from the earlier plans still applies, except "no third-party dependencies". This plan adds the packages above, pinned to exact versions.
  - macOS 15 floor, tools version 6.0.
  - No AI tool mentions anywhere in the repository. Plain imperative commit subjects with no attribution lines.
  - No Arc assets, no telemetry.
  - No WebKit import outside `WebKitEngine`.
- Brow is licensed GPL-3.0. Add the full licence text as `LICENSE` at the repository root.
- The filter lists:
  - EasyList: `https://easylist.to/easylist/easylist.txt`, id `easylist`, title "EasyList".
  - EasyPrivacy: `https://easylist.to/easylist/easyprivacy.txt`, id `easyprivacy`, title "EasyPrivacy".
  - They are Brow's only network requests for this feature, made at most once every 24 hours per list.
- Files live in `~/Library/Application Support/Brow/ContentBlocking/`:
  - the lists as `<id>.txt`
  - AdGuard's engine files in its own `advanced/` subfolder
- Settings live in `UserDefaults`:
  - `BlockAdsAndTrackers` is a Bool, true when missing.
  - `AdBlockingOffSites` is a `[String]` of site keys.
- A site is its registrable domain from the public suffix list (`PublicSuffixList.effectiveTLDPlusOne`), or the whole host when that's nil. Turning blocking off for a site covers every page and frame on that site.
- Each list compiles to its own WebKit rule list. Both are under WebKit's 150,000-rule cap: about 67,000 and 56,000 rules today.
- WebKit doesn't report what a rule list blocked, so Brow shows no blocked counts.

## Review focus

1. **First launch with no network.** Pages load normally with no blocking. Blocking starts once a download succeeds, without a relaunch. (Task 5)
2. **A captive portal or error page instead of a list.** Downloaded HTML, an empty body or a non-200 status must never replace a good list on disk. (Task 4)
3. **Turning a site off.** The site's pages and frames load without rules or page scripts. Other tabs on other sites keep blocking. (Task 2)
4. **Compiling takes seconds.** Converting and compiling never run on the main thread at launch, and pages that load meanwhile simply aren't blocked yet. (Task 5)
5. **Pages can't reach the page-script bridge.** The bridge lives in an isolated content world, so a page's own script can't call it or read its replies. (Task 3)

---

### Task 1: Licence, dependency and site keys

**Files:**
- Create: `LICENSE` (the GPL-3.0 text from `https://www.gnu.org/licenses/gpl-3.0.txt`, unchanged)
- Modify: `README.md` (a "Licence" section and a "Third-party code" list), `docs/design/2026-10-23-brow-design.md` (Decisions: content blocking with AdGuard's SafariConverterLib, Brow is GPL-3.0)
- Modify: `app/Packages/Package.swift`, `app/Brow.xcodeproj/project.pbxproj`
- Create: `app/Packages/Sources/ContentBlocking/SiteKey.swift`
- Modify: `app/Packages/Sources/Browsing/SiteKey.swift`
- Test: `app/Packages/Tests/ContentBlockingTests/SiteKeyTests.swift`, `app/Packages/Tests/BrowsingTests/SiteKeyTests.swift`

**Interfaces:**
- Produces:
  - The `ContentBlocking` library, which depends on `BrowserEngine`, `ContentBlockerConverter` (product from `SafariConverterLib`) and `PublicSuffixList` (product from `swift-psl`)
  - The `ContentBlockingTests` test target
  - `public func contentBlockingSite(for url: URL) -> String?` in `ContentBlocking`. It returns the registrable domain, lowercased, or the host when there is none. It's nil for URLs with no host.
  - `Browsing.siteKey(forHost:)` keeps its signature but now uses `PublicSuffixList.effectiveTLDPlusOne`, which fixes the deferred `t3.gg` case. `Browsing` adds a `PublicSuffixList` dependency.

- [ ] **Step 1: Write the failing tests**

| Test | Input | Expected |
| --- | --- | --- |
| `siteKeys` | `chat.t3.gg` | `t3.gg` |
| (more `siteKeys` rows) | `console.x.ai` | `x.ai` |
| `contentBlockingSites` | `https://news.bbc.co.uk/x` | `bbc.co.uk` |
| | `https://www.fnb.co.za/` | `fnb.co.za` |
| | `http://localhost:8080/` | `localhost` |
| | `about:blank` | nil |

Both new `siteKeys` rows go in the existing table.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter "SiteKeyTests"` from `app/Packages`
Expected: the new `siteKeys` rows fail, and `ContentBlockingTests` doesn't compile.

- [ ] **Step 3: Implement**

- **Package:**
  - Add `.package(url: "https://github.com/AdguardTeam/SafariConverterLib", exact: "4.3.1")`.
  - Get `swift-psl` through it, adding `.package(url: "https://github.com/ameshkov/swift-psl", from: "1.1.0")` only if SwiftPM needs it named directly.
  - Commit `Package.resolved`.
- **Xcode project:** add the `ContentBlocking` product to the app target, following the existing product reference pattern.

- [ ] **Step 4: Run the suite and build the app**

Run: `swift test` and `xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode build`
Expected: all tests pass and `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git commit -am "License Brow under GPL-3.0 and add AdGuard's content blocking library"
```

---

### Task 2: Content rules in the engine

**Files:**
- Create: `app/Packages/Sources/BrowserEngine/ContentBlockingEngine.swift`
- Create: `app/Packages/Sources/WebKitEngine/WebKitContentBlocking.swift`
- Modify: `app/Packages/Sources/WebKitEngine/WebKitEngine.swift`, `WebKitTab.swift`, `app/Packages/Sources/FakeEngine/FakeEngine.swift`
- Test: `app/Packages/Tests/EngineContractTests/ContentBlockingContractTests.swift`

**Interfaces:**
- Produces in `BrowserEngine`:

```swift
public struct ContentRuleSet: Equatable, Sendable {
    public var identifier: String   // stable for the same JSON, so WebKit's compiled copy is reused
    public var json: String         // WebKit content blocker JSON
}

public struct PageScriptlet: Codable, Equatable, Sendable { public var name: String; public var args: [String] }

public struct PageScripts: Codable, Equatable, Sendable {
    public var css: [String]; public var extendedCss: [String]; public var js: [String]; public var scriptlets: [PageScriptlet]
}

@MainActor
public protocol ContentBlockingEngine: BrowserEngine {
    /// Replaces the rule sets every tab uses, compiling any WebKit hasn't seen. Can take seconds the first time.
    func installContentRules(_ ruleSets: [ContentRuleSet]) async throws
    /// Asked before each top-level page load. False loads that page with no rules and no page scripts. Nil means always.
    var isContentBlockingEnabled: (@MainActor (URL) -> Bool)? { get set }
    /// The page scripts for a page or frame, given its URL and its top page's URL. Nil adds nothing.
    var pageScripts: (@MainActor (_ page: URL, _ top: URL?) -> PageScripts?)? { get set }
}
```

- `FakeEngine` conforms. It records `installedRuleSets: [ContentRuleSet]` and keeps both closures.

- [ ] **Step 1: Write the failing contract tests**

These run for every `EngineUnderTest` and use `TestSite`. The page is `<img src="ad-banner.png" onload="document.title='loaded'" onerror="document.title='blocked'">`, and `ad-banner.png` is written next to it as a 1×1 PNG.
- `installedRulesBlockMatchingLoads`
  - Do: install `{"trigger":{"url-filter":"ad-banner\\.png"},"action":{"type":"block"}}`.
  - Expect: the page's title becomes `"blocked"`.
- `pagesLoadNormallyWithoutRules`
  - Expect: with nothing installed, the title becomes `"loaded"`.
- `aSiteWithBlockingOffLoadsEverything`
  - Do: install the same rule, and set `isContentBlockingEnabled` to `{ _ in false }`.
  - Expect: the title becomes `"loaded"`.
- `installingAgainReplacesTheOldRules`
  - Do: install the rule, then install `[]`, then reload.
  - Expect: the title becomes `"loaded"`.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter ContentBlockingContractTests`
Expected: compile errors for `ContentBlockingEngine`.

- [ ] **Step 3: Implement in `WebKitEngine`**

- **Compiling:** `installContentRules` reuses `WKContentRuleListStore.default()` lists by identifier, compiling only identifiers it can't find. It then removes stored lists whose identifier starts with `brow-` and isn't in the new set. The ephemeral test configuration uses a store in a temporary folder instead of the default one.
- **Shared state:** the engine keeps the installed `WKContentRuleList`s. Every tab's `WKUserContentController` gets them on creation and whenever they change.
- **Per-page switch:** in `WebKitTab`'s `decidePolicyFor navigationAction`, before a main-frame navigation goes ahead, the tab asks `engine.isContentBlockingEnabled?(url) ?? true`. It then adds or removes all rule lists on its own content controller.
- **No main-thread JSON work:** encoding never runs on the main actor.

- [ ] **Step 4: Run the suite**

Run: `swift test`
Expected: all tests pass. If WebKit doesn't apply `url-filter` rules to `file://` pages, rule so in the ledger. Then serve the test pages over a loopback `HTTPServer` in the test target instead, with the same assertions.

- [ ] **Step 5: Commit**

```bash
git commit -am "Let engines apply content blocking rules"
```

---

### Task 3: Page scripts for advanced rules

**Files:**
- Create: `scripts/content-blocking/package.json`, `package-lock.json`, `entry.js`, `browser-stub.js`, `build.sh`
- Create: `app/Packages/Sources/WebKitEngine/Resources/content-blocking.js` (generated by `build.sh` and committed)
- Modify: `app/Packages/Package.swift` (`WebKitEngine` gets `resources: [.copy("Resources/content-blocking.js")]`), `.gitignore` (`node_modules/`)
- Modify: `app/Packages/Sources/WebKitEngine/WebKitContentBlocking.swift`
- Test: `app/Packages/Tests/EngineContractTests/ContentBlockingContractTests.swift`

**Interfaces:**
- Consumes: `ContentBlockingEngine.pageScripts` from Task 2.
- Produces: `content-blocking.js` defines `window.__browContentScript = ContentScript` in its own content world. The bootstrap in `entry.js` then does three things:
  1. asks `webkit.messageHandlers.browContentBlocking.postMessage({ page: location.href, top: <top URL or null> })`
  2. awaits the reply
  3. calls `new ContentScript().applyConfiguration({ ...reply, engineTimestamp: 0 })` when the reply isn't null

  The top URL is `null` in the main frame. In frames it's `location.ancestorOrigins[location.ancestorOrigins.length - 1]`.

- [ ] **Step 1: Build the bundle**

- **`package.json`:** pins `@adguard/safari-extension` 4.3.1 and `esbuild` 0.25.11.
- **`build.sh`:** runs `npm ci`, then:

  ```
  npx esbuild entry.js --bundle --format=iife --minify --alias:webextension-polyfill=./browser-stub.js --outfile=../../app/Packages/Sources/WebKitEngine/Resources/content-blocking.js
  ```

- **`browser-stub.js`:** is `export default {};`. Only AdGuard's background script uses the polyfill, and Brow never runs that.
- **Generated file:** starts with a comment naming its sources, their GPL-3.0 licence and `scripts/content-blocking/build.sh`.

- [ ] **Step 2: Write the failing contract tests**

Use a page with `<div id="ad">x</div>` and a script that sets `document.title` to the div's `getComputedStyle(...).display` 500 ms after load.
- `pageScriptsHideElements`
  - Do: set `pageScripts` to `{ _, _ in PageScripts(css: ["#ad"], extendedCss: [], js: [], scriptlets: []) }`.
  - Expect: the title becomes `"none"`.
- `pageScriptsAreSkippedWhenBlockingIsOff`
  - Do: same, plus `isContentBlockingEnabled` set to `{ _ in false }`.
  - Expect: the title becomes `"block"`.
- `pagesCantReachTheBridge`
  - Do: run a page script `document.title = typeof window.webkit?.messageHandlers?.browContentBlocking`.
  - Expect: the title becomes `"undefined"`.

- [ ] **Step 3: Run them and see them fail**

Run: `swift test --filter ContentBlockingContractTests`
Expected: the three new tests fail.

- [ ] **Step 4: Implement**

- **Injection:** every tab's content controller gets `content-blocking.js` from `Bundle.module` as a `WKUserScript`:
  - injection time `.atDocumentStart`
  - `forMainFrameOnly: false`
  - content world `WKContentWorld.world(name: "BrowContentBlocking")`
- **The bridge:** a `WKScriptMessageHandlerWithReply` named `browContentBlocking`, in that same world, answers with:
  - nothing (`nil`) when the frame's top page has blocking off, or `pageScripts` is nil or returns nil
  - otherwise the `PageScripts` encoded as a JSON object
- **Leaks:** the handler holds the engine weakly. `WKUserContentController` retains its handlers, so give it a small forwarding object rather than the engine itself.

- [ ] **Step 5: Run the suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git commit -am "Apply advanced blocking rules with AdGuard's page script"
```

---

### Task 4: Filter lists and conversion

**Files:**
- Create: `app/Packages/Sources/ContentBlocking/FilterList.swift`, `FilterListStore.swift`, `FilterCompiler.swift`, `PageScriptLookup.swift`
- Test: `app/Packages/Tests/ContentBlockingTests/FilterListStoreTests.swift`, `FilterCompilerTests.swift`

**Interfaces:**
- Produces:
  - `public struct FilterList: Equatable, Sendable { public let id: String; public let title: String; public let url: URL; public static let defaults: [FilterList] }`, which holds the two lists from Global constraints.
  - `@MainActor public final class FilterListStore`:
    - `init(folder: URL, now: @escaping @MainActor () -> Date = { .now }, fetch: @escaping @Sendable (URL) async throws -> (Data, Int))`. `Int` is the HTTP status.
    - `func text(for list: FilterList) -> String?`
    - `func refresh(_ lists: [FilterList], maxAge: TimeInterval = 86_400) async -> Bool`. It returns true when any list's text changed.
  - `public struct CompiledFilters: Sendable { public let ruleSets: [ContentRuleSet]; public let advancedRules: String }`
  - `public func compileFilters(_ lists: [(id: String, text: String)]) -> CompiledFilters`. It isn't actor-isolated, so callers run it off the main actor.
  - `@MainActor public final class PageScriptLookup`:
    - `init(advancedRules: String, folder: URL) throws`
    - `func scripts(page: URL, top: URL?) -> PageScripts?`. It returns nil when no rule applies.

- [ ] **Step 1: Write the failing tests**

Store tests, using a fake `fetch` and a clock:
- `downloadsMissingLists`: the text is saved as `<id>.txt` and returned by `text(for:)`.
- `freshListsAreNotDownloadedAgain`: after a refresh, a second refresh 23 hours later makes no fetch.
- `staleListsAreRefreshed`: 25 hours later it fetches again and returns true when the text differs.
- `badDownloadsKeepTheOldList`: none of these replace the saved text, and refresh returns false:
  - a 503 status
  - an empty body
  - an HTML body (`<!DOCTYPE html>…`)
  - a body whose first non-empty line doesn't start with `[Adblock`
  - a thrown error

Compiler tests use this text: `[Adblock Plus 2.0]\n||ads.example.com^\nexample.com##.banner\nexample.com#%#//scriptlet('abort-on-property-read', 'adsbygoogle')`.
- `compilingMakesOneRuleSetPerList`
  - Do: compile two lists with ids `a` and `b`.
  - Expect:
    - two rule sets, with identifiers starting `brow-a-` and `brow-b-`
    - each `json` holds a rule whose `url-filter` contains `ads\\.example\\.com`
- `identifiersFollowTheContent`
  - Expect: the same text gives the same identifier, and a changed text gives a different one. Identifiers are `brow-<id>-` plus the first 16 hex characters of the JSON's SHA-256.
- `scriptletsBecomeAdvancedRules`
  - Expect: `advancedRules` contains `abort-on-property-read`.
- `lookupFindsScriptletsForTheirSite`
  - Expect:
    - `PageScriptLookup(...).scripts(page: https://example.com/, top: nil)?.scriptlets.map(\.name) == ["abort-on-property-read"]`
    - `https://other.org/` returns nil

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter ContentBlockingTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

- **`compileFilters`:** calls `ContentBlockerConverter().convertArray(rules:safariVersion: .autodetect(), advancedBlocking: true)` once per list. The advanced texts join with newlines.
- **`PageScriptLookup`:** wraps `WebExtension(containerURL: folder)`, calls `buildFilterEngine(rules:)` and maps `lookup(pageUrl:topUrl:)` to `PageScripts`. An empty configuration returns nil.
- **Saving lists:** writes are atomic.

- [ ] **Step 4: Run the suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git commit -am "Download filter lists and convert them with AdGuard's converter"
```

---

### Task 5: The content blocker

**Files:**
- Create: `app/Packages/Sources/ContentBlocking/ContentBlocker.swift`
- Test: `app/Packages/Tests/ContentBlockingTests/ContentBlockerTests.swift`

**Interfaces:**
- Consumes: Tasks 2 and 4.
- Produces: `@MainActor @Observable public final class ContentBlocker`:
  - `init(engine: (any ContentBlockingEngine)?, store: FilterListStore, workFolder: URL, lists: [FilterList] = FilterList.defaults, defaults: UserDefaults = .standard)`
  - `public private(set) var isEnabled: Bool` and `public func setEnabled(_ enabled: Bool)`. Both are backed by `BlockAdsAndTrackers`.
  - `public func isBlocking(on url: URL) -> Bool`. False when blocking is off globally or for the URL's site, true for URLs with no site.
  - `public func setBlocking(_ on: Bool, forSiteOf url: URL)`. Backed by `AdBlockingOffSites`.
  - `public func start() async`. It hooks up the engine's two closures, compiles and installs whatever lists are on disk, then refreshes and recompiles if anything changed.
  - `public func refreshIfNeeded() async`

- [ ] **Step 1: Write the failing tests**

Each test uses a fresh `UserDefaults(suiteName:)`, a `FakeEngine`, and a store with fake fetch.
- `startInstallsSavedListsBeforeDownloading`
  - Do: put both lists on disk, with fetch suspended until released.
  - Expect: after `start()` returns, or once the first install happens, `installedRuleSets` has 2 entries.
- `firstLaunchOfflineBlocksNothingAndRecovers`
  - Do: fetch throws, so `start()` installs nothing. Then fetch succeeds and `refreshIfNeeded()` runs.
  - Expect: 2 rule sets installed.
- `blockingIsOnByDefault`
  - Expect: `isEnabled` is true, and `isBlocking(on: https://a.example.com/)` is true.
- `turningASiteOffCoversItsSubdomains`
  - Do: `setBlocking(false, forSiteOf: https://www.example.com/)`.
  - Expect:
    - `isBlocking(on: https://shop.example.com/)` is false.
    - `isBlocking(on: https://example.org/)` is true.
    - The setting survives a new `ContentBlocker` on the same defaults.
- `turningBlockingOffGloballyStopsEverySite`
  - Do: `setEnabled(false)`.
  - Expect: the engine's `isContentBlockingEnabled` closure returns false for any URL.
- `pageScriptsFollowTheSiteSetting`
  - Expect:
    - With the compiler test's scriptlet list saved, the engine's `pageScripts` closure returns a scriptlet for `https://example.com/`.
    - After turning that site off, it returns nil.

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter ContentBlockerTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

- **Off the main thread:** `compileFilters` and `installContentRules` don't run on the main actor. Use a detached task for compiling.
- **Rebuilds:** `PageScriptLookup` is rebuilt on the main actor after each compile. Its folder is `workFolder/advanced`.
- **One at a time:** overlapping `refreshIfNeeded` calls share one run.

- [ ] **Step 4: Run the suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git commit -am "Coordinate filter lists, settings and the engine for content blocking"
```

---

### Task 6: Turning it on in the app

**Files:**
- Modify: `app/Brow/AppDelegate.swift`, `app/Brow/MainMenu.swift`, `app/Brow/BrowserWindowController.swift`, `app/Brow/CommandBarPresenter.swift`, `README.md`

**Interfaces:**
- Consumes: `ContentBlocker` from Task 5.

- [ ] **Step 1: Wire it up**

There are no app-target tests for this task.
- **`AppDelegate`:**
  - Creates one `ContentBlocker`, passing the shared `WebKitEngine` as the engine and a `FilterListStore` that fetches with `URLSession.shared`.
  - Starts it in a `Task` at launch.
  - Calls `refreshIfNeeded()` every 6 hours and on wake, the same way `ArchiveSweeper` schedules its timer.
- **Brow menu:** "Block Ads and Trackers", a checkmark item that calls `setEnabled` and reloads the selected tab in every window.
- **Tab menu:** "Block Ads on This Site", a checkmark showing `isBlocking(on:)` for the selected tab's URL.
  - It's disabled when global blocking is off, or the page isn't http or https.
  - Choosing it calls `setBlocking(_:forSiteOf:)` and reloads the selected tab.
- **Command bar:** command `toggle-site-blocking`, "Turn Ad Blocking On or Off for This Site", keywords `["adblock", "ads", "tracker", "shield"]`. It does the same as the Tab menu item.

- [ ] **Step 2: Update the README**

- Add a sentence to the "Brow is early" paragraph saying it blocks ads and trackers with EasyList and EasyPrivacy.
- Add `ContentBlocking` to the module list.

- [ ] **Step 3: Build and check by hand**

Run: `swift test` and the `xcodebuild` command.
Expected: all tests pass and `BUILD SUCCEEDED`. Then check by hand:
1. Launch online, wait about 10 seconds, and open a news site. Ads should be gone.
2. Turn the site off from the Tab menu. The page should reload with ads.
3. Quit and relaunch. The site setting should be kept, and blocking should start without downloading again.

- [ ] **Step 4: Commit**

```bash
git commit -am "Block ads and trackers in Brow, with a switch per site"
```
