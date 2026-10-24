# YouTube ad blocking implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** Brow blocks YouTube's video ads by using AdGuard's Base filter list instead of EasyList, and by putting a page's scriptlets in place before any of the page's own scripts run.

**Architecture:**
- **The list:** `FilterList.defaults` swaps EasyList for AdGuard Base (Safari build), which is EasyList plus AdGuard's own rules, including YouTube's `set-constant` scriptlets.
- **Earlier rules:** `WebKitTab` already decides each top-level navigation before it starts. At that point it now looks up the new page's `PageScripts` and puts them into an early user script that runs first at document start. The bundled content script then applies them straight away, without waiting on the asynchronous bridge. Frames keep using the bridge.

**Tech stack:** Swift 6, SwiftPM, Swift Testing, WebKit (only in `WebKitEngine`), the existing esbuild bundle in `scripts/content-blocking`.

**Spec:** `docs/design/2026-10-23-brow-design.md`, Decisions: content blocking with AdGuard's SafariConverterLib.

## Global constraints

- Everything from earlier plans applies:
  - No AI tool mentions in the repository.
  - No WebKit import outside `WebKitEngine`.
  - Every `xcodebuild` command uses `-skipPackagePluginValidation`.
- AdGuard Base, Safari build: `https://filters.adtidy.org/extension/safari/filters/2.txt`, id `adguard-base`, title "AdGuard Base". GPL-3.0, like the rest of AdGuard's code. EasyPrivacy stays.
- AdGuard lists start with `!` comment lines such as `! Title: AdGuard Base filter`, not `[Adblock Plus 2.0]`. The download check accepts either form.

## Review focus

1. **The first load of a YouTube watch page.** The scriptlets are in place before YouTube's inline `ytInitialPlayerResponse` script runs. (Task 2)
2. **A site with ad blocking turned off.** It gets no early rules either. (Task 2)
3. **A redirect to another site.** The early rules are those of the site the page actually lands on, or there are none. They are never the first site's rules on the second site. (Task 2)
4. **An old `easylist.txt` left on disk.** It no longer counts toward the rules, and isn't downloaded again. (Task 1)
5. **A converted list over 150,000 rules.** It must still compile in WebKit. (Task 1)

---

### Task 1: AdGuard Base instead of EasyList

**Files:**
- Modify: `app/Packages/Sources/ContentBlocking/FilterList.swift`, `FilterListStore.swift`
- Test: `app/Packages/Tests/ContentBlockingTests/FilterListStoreTests.swift`, `FilterCompilerTests.swift`

**Interfaces:**
- Produces:
  - `FilterList.adGuardBase`
  - `FilterList.defaults == [.adGuardBase, .easyPrivacy]`
  - `FilterListStore.looksLikeFilterList(_:)` accepts a list whose first non-empty line starts with `[Adblock`, or whose first 30 lines include a `! Title:` line.

- [ ] **Step 1: Failing tests**
  - `adGuardStyleListsAreAccepted`: a download of `"! Checksum: x\n! Title: AdGuard Base filter\n||ads.example.com^\n"` with status 200 is saved.
  - `defaultsUseAdGuardBase`: `FilterList.defaults.map(\.id) == ["adguard-base", "easyprivacy"]`.
  - The existing `badDownloadsKeepTheOldList` cases must still be rejected, including the `"! Title: something else"` case. That case only fails because it has no `[Adblock` header and no `! Title:` line within 30 lines, so it becomes `"! something else\n||x.example.com^\n"`.

- [ ] **Step 2: Run and see them fail, implement, see them pass**

Run: `swift test --filter ContentBlockingTests`
Expected: the two new tests fail, then pass.

- [ ] **Step 3: Check the real list fits**

Run a one-off test that converts the downloaded AdGuard Base with `compileFilters`. Expected: `safariRulesCount` at or below 150,000, from the converter's result. If it's over, cap it by passing `maxJsonSizeBytes` or splitting the list, and record a ruling.

- [ ] **Step 4: Commit**

```bash
git commit -am "Use AdGuard Base instead of EasyList for ad blocking"
```

---

### Task 2: Page rules before the page's own scripts

**Files:**
- Modify: `scripts/content-blocking/entry.js`, then rebuild `app/Packages/Sources/WebKitEngine/Resources/content-blocking.js` with `scripts/content-blocking/build.sh`
- Modify: `app/Packages/Sources/WebKitEngine/WebKitContentBlocking.swift`, `WebKitTab.swift`
- Test: `app/Packages/Tests/EngineContractTests/ContentBlockingContractTests.swift`

**Interfaces:**
- Consumes: `ContentBlockingEngine.pageScripts` and `isContentBlockingEnabled`.
- Produces:
  - `PageScriptInjection.install(on:bridge:early:)`, where `early: PageScripts?`. It adds a document-start, main-frame-only user script in the `BrowContentBlocking` world that sets `window.__browEarlyRules` to the JSON, before adding the bundle.
  - `WebKitTab` re-installs its scripts on every allowed main-frame navigation, before the navigation starts.

- [ ] **Step 1: Failing contract tests**
  - `scriptletsRunBeforeThePagesFirstScript`
    - Do: set `pageScripts` to return `PageScripts(css: [], extendedCss: [], js: [], scriptlets: [PageScriptlet(name: "set-constant", args: ["browTestFlag", "true"])])`. The page's first and only script is `<script>document.title = String(window.browTestFlag)</script>`.
    - Expect: the title becomes `"true"`.
  - `earlyRulesFollowTheSiteSetting`
    - Do: same, with `isContentBlockingEnabled = { _ in false }`.
    - Expect: the title becomes `"undefined"`.
  - `earlyRulesBelongToTheNewPage`
    - Do: `pageScripts` returns the scriptlet only for pages named `a.html`. Load `a.html`, then `b.html`, which has the same probe script.
    - Expect: the title becomes `"undefined"` on `b.html`.

- [ ] **Step 2: Run them and see `scriptletsRunBeforeThePagesFirstScript` fail**

Run: `swift test --filter ContentBlockingContractTests`
Expected: the old asynchronous bridge applies the scriptlet too late, so the title is `"undefined"`.

- [ ] **Step 3: Implement**

- **`entry.js`:** in the main frame, when `window.__browEarlyRules` is set, apply it at once and skip the bridge. Otherwise ask the bridge, as now. Rebuild with `build.sh`.
- **`WebKitTab`:** on an allowed main-frame navigation, call `removeAllUserScripts()`, then `PageScriptInjection.install` with `early = isBlocking ? engine.pageScripts?(url, nil) : nil`. The bridge handler stays registered, so don't add it again. Split `install` so only the scripts are re-added.
- **Redirects:** when the committed URL's site differs from the one the early rules were made for, re-install the scripts in `didCommit` for the committed URL. They will apply from the next load.

- [ ] **Step 4: Run the suite, build and commit**

Run: `swift test` and the `xcodebuild` Debug build.
Expected: all tests pass and `BUILD SUCCEEDED`.

```bash
git commit -am "Apply a page's blocking rules before its own scripts run"
```

---

### Task 3: Check YouTube by hand and document it

- [ ] **Step 1:** In the README's third-party list, change EasyList to "AdGuard Base (GPL-3.0) and EasyPrivacy".
- [ ] **Step 2:** Relaunch Brow, then open two YouTube videos in a row (the owner checks). Expected: no pre-roll ads. Record what's seen in the final message.
- [ ] **Step 3:** Commit.

```bash
git commit -am "Note AdGuard Base in the README"
```
