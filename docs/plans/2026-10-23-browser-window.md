# Browser window implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** A Brow app that opens a window and browses real websites on WebKit, with tabs, an address bar, back and forward, sign-in popups and JavaScript dialogs. The UI talks only to engine protocols, so Chromium can replace WebKit later.

**Architecture:** Four new modules in the `BrowKit` package. `BrowserEngine` holds the protocols and value types and imports only AppKit. `FakeEngine` implements them for tests. `WebKitEngine` implements them on `WKWebView`. `Browsing` holds the engine-agnostic window state: the tab list, selection rules, popups, dialog queue and address bar parsing. A new Xcode project at `app/Brow.xcodeproj` builds `Brow.app` from AppKit code in `app/Brow` that depends on those modules. The tab list in this plan is a temporary plain table. Plan 3 replaces it with the real sidebar.

**Tech stack:** Swift 6 language mode, SwiftPM, Swift Testing, AppKit, WebKit, Observation. Xcode 27 to build the app. No third-party dependencies.

**Spec:** `docs/design/2026-10-23-brow-design.md`, section "Browser engines" and step 3 of "Order before the new Mac arrives".

**Next plans:** the sidebar UI (spaces, pinned tabs, folders, favourites, drag and drop, swiping), then archiving, command bar, split view and Peek, then sync.

## Global constraints

- Everything from the foundation plan still applies: macOS 15 floor, tools version 6.0, no AI tool mentions anywhere in the repository, plain imperative commit subjects with no attribution lines, no Arc assets, no telemetry.
- No `WebKit` import outside `Sources/WebKitEngine` and its tests. No `WKWebView` or other WebKit type in any public signature of `BrowserEngine`, `Browsing` or the app.
- Every engine type and protocol is `@MainActor`.
- Tests never touch the default WebKit data store. They use `.ephemeral` storage.
- The app's bundle identifier is `app.brow.Brow`. The owner confirms or changes it before the CloudKit plan.
- The default search engine is Google, matching Arc: `https://www.google.com/search?q=<query>`.
- The app isn't sandboxed and uses ad hoc signing (`CODE_SIGN_IDENTITY = "-"`) until the release plan.

## Review focus

1. **Sign-in popups.** "Sign in with Google" and similar flows call `window.open`, need `window.opener` in the popup, then call `window.close()`. The popup must open as a tab after its opener, keep the opener link, and close itself back to the opener. (Tasks 3 and 4)
2. **JavaScript dialogs.** `alert`, `confirm` and `prompt` must always get an answer. A dialog in a background tab waits until that tab is selected, and closing a tab with an open dialog answers it as dismissed instead of hanging the page. (Tasks 3 and 4)
3. **What people type in the address bar.** `localhost:3000`, `192.168.1.1:8080/admin`, `foo.dev`, `c++ & rust` and `version 1.2` each go to the place a person expects: local server, router, website, search, search. (Task 2)
4. **Sites that block unfamiliar browsers.** WebKit's default user agent has no `Safari/` token, so Google and others serve degraded pages or block sign-in. Brow's user agent must include `Version/<Safari version> Safari/605.1.15`. (Task 4)
5. **Closing the selected tab.** The next selection is the opener if the closed tab was a popup, otherwise the tab below, otherwise the tab above. (Task 3)

---

### Task 1: Engine protocols and the fake engine

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/BrowserEngine/BrowserEngine.swift`
- Create: `app/Packages/Sources/BrowserEngine/BrowserTab.swift`
- Create: `app/Packages/Sources/BrowserEngine/BrowserTabDelegate.swift`
- Create: `app/Packages/Sources/BrowserEngine/JavaScriptDialog.swift`
- Create: `app/Packages/Sources/FakeEngine/FakeEngine.swift`
- Create: `app/Packages/Sources/FakeEngine/FakeTab.swift`
- Test: `app/Packages/Tests/FakeEngineTests/FakeTabTests.swift`

**Interfaces:**
- Produces, all `public`, in `BrowserEngine`:
  - `struct TabID: Hashable, Sendable, CustomStringConvertible` wrapping `rawValue: UUID`, with `static func make() -> TabID`.
  - `struct TabState: Equatable, Sendable` with `url: URL?`, `title: String?`, `isLoading: Bool`, `estimatedProgress: Double`, `canGoBack: Bool`, `canGoForward: Bool`, and `static let blank` (all nil, false or 0).
  - `@MainActor protocol BrowserEngine: AnyObject` with `func makeTab(url: URL?) -> any BrowserTab`.
  - `@MainActor protocol BrowserTab: AnyObject, Observable` with `var id: TabID { get }`, `var state: TabState { get }`, `var contentView: NSView { get }`, `var delegate: (any BrowserTabDelegate)? { get set }`, `func load(_ url: URL)`, `func goBack()`, `func goForward()`, `func reload()`, `func stopLoading()`, `func close()`.
  - `enum NewTabDisposition: Sendable { case foreground, background }`.
  - `@MainActor protocol BrowserTabDelegate: AnyObject` with `func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition)`, `func tabDidRequestClose(_ tab: any BrowserTab)` and `func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult`.
  - `enum JavaScriptDialog: Equatable, Sendable { case alert(message: String), confirm(message: String), prompt(message: String, defaultText: String?) }`.
  - `enum JavaScriptDialogResult: Equatable, Sendable { case accepted(text: String?), dismissed }`.
- Produces, in `FakeEngine`:
  - `final class FakeEngine: BrowserEngine` with `init()` and `private(set) var madeTabs: [FakeTab]`.
  - `@Observable final class FakeTab: BrowserTab` with `private(set) var loadedURLs: [URL]`, `private(set) var isClosed: Bool`, and test hooks `func finishLoading(title: String?)`, `func simulateOpen(url: URL?, disposition: NewTabDisposition) -> FakeTab`, `func simulateRequestClose()`, `func simulateDialog(_ dialog: JavaScriptDialog) async -> JavaScriptDialogResult`.

- [ ] **Step 1: Add the targets**

Add library products and targets `BrowserEngine` (no dependencies) and `FakeEngine` (depends on `BrowserEngine`), and test target `FakeEngineTests` (depends on `FakeEngine`, `BrowserEngine`).

- [ ] **Step 2: Write the failing tests**

All tests are `@MainActor`.

```swift
@Test func loadStartsLoadingAndRecordsURL()        // url set, isLoading true, title nil, loadedURLs == [a]
@Test func finishLoadingSetsTitle()                 // isLoading false, title "A", estimatedProgress 1
@Test func historyBackAndForward() {
    // load a, finish, load b, finish
    // canGoBack true, canGoForward false
    // goBack -> url a, canGoForward true; goForward -> url b
    // goBack then load c drops b from forward history: canGoForward false
}
@Test func simulateOpenReachesDelegate()            // delegate gets (source, newTab, .background); newTab.state.url == the URL; engine.madeTabs.count == 2
@Test func simulateDialogWithoutDelegateIsDismissed() async  // == .dismissed
@Test func closeMarksClosed()                       // isClosed true
```

The delegate in these tests is a small `RecordingDelegate` class in the test file.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter FakeEngineTests`
Expected: build fails because the types don't exist.

- [ ] **Step 4: Implement the protocols and the fake**

`FakeTab` keeps a back/forward list as `[URL]` plus an index. `load` drops forward entries. `FakeEngine.makeTab(url:)` creates a tab, calls `load` when the URL isn't nil, and appends it to `madeTabs`. `simulateOpen` creates its new tab through the same engine.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter FakeEngineTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add browser engine protocols and fake engine"
```

---

### Task 2: Address bar input and tab titles

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/Browsing/AddressInput.swift`
- Create: `app/Packages/Sources/Browsing/DisplayTitle.swift`
- Test: `app/Packages/Tests/BrowsingTests/AddressInputTests.swift`
- Test: `app/Packages/Tests/BrowsingTests/DisplayTitleTests.swift`

**Interfaces:**
- Consumes: `TabState` from Task 1.
- Produces, in `Browsing`:
  - `enum AddressInput { static func resolve(_ text: String) -> URL? }`
  - `func displayTitle(for state: TabState) -> String`

- [ ] **Step 1: Add the targets**

Library product and target `Browsing` (depends on `BrowserEngine`). Test target `BrowsingTests` (depends on `Browsing`, `BrowserEngine`, `FakeEngine`).

- [ ] **Step 2: Write the failing tests**

`AddressInputTests` is one parameterized test plus one for empty input:

```swift
@Test(arguments: [
    ("example.com", "https://example.com"),
    ("  example.com/path?q=1  ", "https://example.com/path?q=1"),
    ("foo.dev", "https://foo.dev"),
    ("http://example.com", "http://example.com"),
    ("https://example.com/a b", "https://example.com/a%20b"),
    ("localhost:3000", "http://localhost:3000"),
    ("localhost", "http://localhost"),
    ("192.168.1.1:8080/admin", "http://192.168.1.1:8080/admin"),
    ("about:blank", "about:blank"),
    ("file:///Users/me/page.html", "file:///Users/me/page.html"),
    ("what is swift", "https://www.google.com/search?q=what%20is%20swift"),
    ("swift", "https://www.google.com/search?q=swift"),
    ("c++ & rust", "https://www.google.com/search?q=c%2B%2B%20%26%20rust"),
    ("version 1.2", "https://www.google.com/search?q=version%201.2"),
    ("1.5", "https://www.google.com/search?q=1.5"),
])
func resolves(input: String, expected: String) {
    #expect(AddressInput.resolve(input)?.absoluteString == expected)
}

@Test func blankInputResolvesToNil()   // "" and "   " -> nil
```

`DisplayTitleTests`:

```swift
@Test func usesTrimmedTitle()          // title "  Inbox  " -> "Inbox"
@Test func fallsBackToHost()           // title "" and url https://mail.example.com/x -> "mail.example.com"
@Test func blankTabIsNewTab()          // url nil -> "New Tab"; url about:blank with no title -> "New Tab"
@Test func fileURLUsesFileName()       // file:///Users/me/page.html with no title -> "page.html"
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter BrowsingTests`
Expected: build fails.

- [ ] **Step 4: Implement `AddressInput.resolve` and `displayTitle`**

`resolve` applies these rules in order to the trimmed text:

1. Empty gives nil.
2. Text starting with `http://`, `https://` or `file://`, or equal to or starting with `about:`, is used as a URL. Spaces get percent-encoded first.
3. Text containing whitespace is a search.
4. `localhost` or an IPv4 address, optionally followed by `:port` and a path, gets `http://`.
5. Text whose host part (before the first `/`, `?` or `:`) contains a dot and ends in a label of two or more letters gets `https://`.
6. Anything else is a search. The query is percent-encoded with `.urlQueryAllowed` minus `+`, `&`, `=`, `?` and `#`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter BrowsingTests`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/Packages
git commit -m "Add address bar input parsing and tab titles"
```

---

### Task 3: Browser window model

**Files:**
- Create: `app/Packages/Sources/Browsing/BrowserWindowModel.swift`
- Create: `app/Packages/Sources/Browsing/PendingDialog.swift`
- Test: `app/Packages/Tests/BrowsingTests/BrowserWindowModelTests.swift`

**Interfaces:**
- Consumes: everything in Task 1. `FakeEngine` in tests.
- Produces, in `Browsing`:
  - `@MainActor @Observable final class BrowserWindowModel: BrowserTabDelegate` with:
    - `init(engine: any BrowserEngine)`
    - `private(set) var tabs: [any BrowserTab]`, `private(set) var selectedTabID: TabID?`, `var selectedTab: (any BrowserTab)? { get }`
    - `@discardableResult func openTab(url: URL?, select: Bool = true) -> any BrowserTab` appends at the end.
    - `func select(_ id: TabID)`, `func close(_ id: TabID)`, `func selectNext()`, `func selectPrevious()`, `func select(number: Int)` (1 to 8 pick by position, 9 picks the last tab)
    - `var dialogForSelectedTab: PendingDialog? { get }`, `func resolveDialog(_ id: PendingDialog.ID, with result: JavaScriptDialogResult)`
  - `struct PendingDialog: Identifiable, Equatable` with `id: UUID`, `tabID: TabID`, `dialog: JavaScriptDialog`.

- [ ] **Step 1: Write the failing tests**

All tests are `@MainActor` and use a `FakeEngine`. Tabs are named by the URL they load.

```swift
@Test func openTabAppendsAndSelects()
@Test func openTabInBackgroundKeepsSelection()       // select: false
@Test func closingSelectedSelectsTabBelow()          // [a, b, c] select b, close b -> c selected
@Test func closingLastSelectsTabAbove()              // [a, b, c] select c, close c -> b selected
@Test func closingOnlyTabLeavesNoSelection()         // tabs empty, selectedTabID nil
@Test func closeCallsTabClose()                      // FakeTab.isClosed true
@Test func foregroundPopupOpensAfterOpenerAndIsSelected() // [a, b], a.simulateOpen(.foreground) -> [a, p, b], p selected
@Test func backgroundOpensKeepOrderAfterOpener() {
    // [a, b], select a, a opens c1 then c2 in background -> [a, c1, c2, b], a still selected
}
@Test func closingPopupReturnsToOpener()             // [a, b, p opened by a] select p, close p -> a selected
@Test func popupRequestingCloseIsClosed()            // p.simulateRequestClose() -> p gone, isClosed true
@Test func selectNextAndPreviousWrap()
@Test func selectNumberNineIsLast()                  // 4 tabs, select(number: 9) -> 4th; select(number: 2) -> 2nd; select(number: 7) does nothing
@Test func dialogOnSelectedTabWaitsForAnswer() async {
    // start Task { await tab.simulateDialog(.confirm(message: "Leave?")) }
    // wait until dialogForSelectedTab?.dialog == .confirm(message: "Leave?")
    // resolveDialog(id, with: .accepted(text: nil)) -> the task returns .accepted(text: nil), dialogForSelectedTab nil
}
@Test func dialogInBackgroundTabWaitsUntilSelected() async  // dialogForSelectedTab nil while b selected; select a -> visible
@Test func closingTabDismissesItsDialog() async             // close the tab -> the task returns .dismissed
```

Use a helper `func eventually(_ condition: @MainActor () -> Bool) async throws` that polls every 10 ms for up to 2 seconds and records an issue on timeout.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter BrowserWindowModelTests`
Expected: build fails.

- [ ] **Step 3: Implement `BrowserWindowModel`**

The model sets itself as the delegate of every tab it holds and stores `openerIDs: [TabID: TabID]`. Closing a tab removes it from the opener map, both as a child and as an opener. New tabs from a delegate callback go after the last tab in the run of tabs directly after the source whose opener is the source.

Close selection rule when the closed tab was selected: the opener if it's still open, otherwise the tab now at the closed index, otherwise the last tab, otherwise nil.

Dialogs are stored as `PendingDialog` plus a `CheckedContinuation<JavaScriptDialogResult, Never>`, in order of arrival. `dialogForSelectedTab` is the first one whose `tabID` is the selected tab. Closing a tab resumes all of its continuations with `.dismissed`. Every continuation must be resumed exactly once.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages --filter BrowsingTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/Packages
git commit -m "Add browser window model"
```

---

### Task 4: WebKit engine

**Files:**
- Modify: `app/Packages/Package.swift`
- Create: `app/Packages/Sources/WebKitEngine/WebKitEngine.swift`
- Create: `app/Packages/Sources/WebKitEngine/WebKitTab.swift`
- Create: `app/Packages/Sources/WebKitEngine/SafariUserAgent.swift`
- Create: `app/Packages/Sources/WebKitEngine/LinkDisposition.swift`
- Test: `app/Packages/Tests/WebKitEngineTests/SafariUserAgentTests.swift`
- Test: `app/Packages/Tests/WebKitEngineTests/LinkDispositionTests.swift`
- Test: `app/Packages/Tests/EngineContractTests/EngineContractTests.swift`
- Test: `app/Packages/Tests/EngineContractTests/TestSite.swift`

**Interfaces:**
- Consumes: Task 1 protocols.
- Produces, in `WebKitEngine`:
  - `final class WebKitEngine: BrowserEngine` with `init(configuration: Configuration = .init())`.
  - `struct WebKitEngine.Configuration` with `var storage: Storage = .persistent` (`enum Storage { case persistent, ephemeral }`) and `var allowsPopupsWithoutUserGesture = false`.
  - Internal, for tests: `func safariApplicationName(infoPlistURL: URL) -> String` and `func newTabDisposition(modifiers: NSEvent.ModifierFlags, buttonNumber: Int) -> NewTabDisposition?`.

A quick check on this Mac already showed `WKWebView` loads file URLs, runs `alert`, and opens a `window.open` popup with `window.opener` set, all inside `swift test`. So the contract tests below run headless.

- [ ] **Step 1: Add the targets**

Library product and target `WebKitEngine` (depends on `BrowserEngine`). Test targets `WebKitEngineTests` (depends on `WebKitEngine`, `BrowserEngine`) and `EngineContractTests` (depends on `WebKitEngine`, `BrowserEngine`).

- [ ] **Step 2: Write the failing unit tests**

```swift
@Test func applicationNameUsesSafariVersion()    // plist with CFBundleShortVersionString "27.0" -> "Version/27.0 Safari/605.1.15"
@Test func applicationNameFallsBackWhenMissing() // missing file -> "Version/27.0 Safari/605.1.15"

@Test func plainClickStaysInTab()                // [] , button 0 -> nil
@Test func commandClickOpensInBackground()       // [.command], 0 -> .background
@Test func commandShiftClickOpensInForeground()  // [.command, .shift], 0 -> .foreground
@Test func middleClickOpensInBackground()        // [], 2 -> .background
```

- [ ] **Step 3: Write the failing contract tests**

The suite is `@MainActor` and `.serialized`. Each test takes `@Test(arguments: EngineUnderTest.allCases)`, where `enum EngineUnderTest: CaseIterable { case webKit }` has `func make() -> any BrowserEngine`. The `.webKit` case builds `WebKitEngine(configuration: .init(storage: .ephemeral, allowsPopupsWithoutUserGesture: true))`. The Chromium plan adds a case here.

`TestSite` writes HTML pages into a fresh temporary folder and returns their file URLs. Wait with an `eventually` helper that polls every 50 ms for up to 10 seconds. The `RecordingDelegate` makes itself the delegate of every tab it's told about, so it also hears from popups.

```swift
@Test func loadUpdatesURLAndTitle(engine:)    // a.html "<title>A</title>" -> url == a, title "A", isLoading false
@Test func backAndForward(engine:)            // a then b; goBack -> "A", canGoForward; goForward -> "B"
@Test func popupKeepsOpener(engine:)          // page calls window.open("child.html"); child sets document.title = window.opener ? "has opener" : "no opener"
                                              // delegate gets didOpen with .foreground; newTab.state.title == "has opener"
@Test func popupCanCloseItself(engine:)       // child calls window.close() after 100 ms -> delegate gets tabDidRequestClose(newTab)
@Test func confirmUsesDelegateAnswer(engine:) // document.title = confirm("ok?") ? "yes" : "no"; delegate answers .accepted -> "yes"
@Test func promptReturnsDelegateText(engine:) // document.title = prompt("name?", "x"); delegate answers .accepted(text: "Brow") -> "Brow"; recorded dialog == .prompt(message: "name?", defaultText: "x")
@Test func dialogsWithoutDelegateCancel(engine:) // no delegate, confirm page -> "no"
@Test func userAgentLooksLikeAFullBrowser(engine:) // document.title = navigator.userAgent -> contains "Safari/"
@Test func closeDetachesContentView(engine:)  // add contentView to a superview, close() -> superview nil
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test --package-path app/Packages --filter "WebKitEngineTests|EngineContractTests"`
Expected: build fails.

- [ ] **Step 5: Implement the engine**

`WebKitEngine` builds each new tab's `WKWebViewConfiguration` the same way. It sets the data store from `storage`, `applicationNameForUserAgent` from `safariApplicationName(infoPlistURL: /Applications/Safari.app/Contents/Info.plist)`, `preferences.isElementFullscreenEnabled = true` and `preferences.javaScriptCanOpenWindowsAutomatically` from the configuration.

`WebKitTab` is `@Observable`. It's an `NSObject` that is the web view's navigation and UI delegate. Its `contentView` is the `WKWebView`, with `allowsBackForwardNavigationGestures`, `allowsMagnification` and `isInspectable` turned on. It mirrors `url`, `title`, `isLoading`, `estimatedProgress`, `canGoBack` and `canGoForward` into `state` through key-value observation. `load` uses `loadFileURL(_:allowingReadAccessTo:)` with the file's folder for file URLs and `load(URLRequest)` for everything else.

- `createWebViewWith` builds a new `WebKitTab` around a web view made from the configuration WebKit passes in, calls `didOpen` with `.foreground`, and returns the web view. It returns nil when there's no delegate.
- `decidePolicyFor navigationAction` checks `newTabDisposition` for link clicks. When it gives a disposition, the tab cancels the navigation and opens the URL in a new tab from the engine with that disposition.
- `webViewDidClose` calls `tabDidRequestClose`.
- The three JavaScript panel methods map to `JavaScriptDialog` and ask the delegate. With no delegate they use `.dismissed`. `confirm` is true only for `.accepted`. `prompt` returns the accepted text, or nil.
- `webViewWebContentProcessDidTerminate` reloads the page once.
- `close()` stops loading, removes the web view from its superview, clears both delegates, and loads `about:blank` so media stops.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path app/Packages`
Expected: the whole suite passes, including 6 unit and 9 contract tests here.

- [ ] **Step 7: Commit**

```bash
git add app/Packages
git commit -m "Add WebKit browser engine"
```

---

### Task 5: The Brow app

**Files:**
- Create: `app/Brow.xcodeproj/project.pbxproj`
- Create: `app/Brow.xcodeproj/xcshareddata/xcschemes/Brow.xcscheme`
- Create: `app/Support/Info.plist`
- Create: `app/Brow/main.swift`
- Create: `app/Brow/AppDelegate.swift`
- Create: `app/Brow/MainMenu.swift`
- Create: `app/Brow/BrowserWindowController.swift`
- Create: `app/Brow/TabListViewController.swift`
- Create: `app/Brow/WebContentViewController.swift`
- Create: `app/Brow/DialogPresenter.swift`
- Create: `app/Brow/ObservationLoop.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `BrowserWindowModel`, `AddressInput`, `displayTitle` from Tasks 2 and 3. `WebKitEngine` from Task 4.

The app has no unit tests. Its logic lives in the package. This task is verified by a clean build and the hands-on checklist in Step 4.

- [ ] **Step 1: Create the Xcode project**

Write `project.pbxproj` by hand with `objectVersion = 77`. It contains:

- One macOS app target `Brow` whose sources come from a `PBXFileSystemSynchronizedRootGroup` for the `Brow` folder, so new Swift files are picked up without editing the project.
- An `XCLocalSwiftPackageReference` with `relativePath = Packages`. The target links products `BrowserEngine`, `Browsing` and `WebKitEngine`.
- Build settings: `PRODUCT_NAME = Brow`, `PRODUCT_BUNDLE_IDENTIFIER = app.brow.Brow`, `MACOSX_DEPLOYMENT_TARGET = 15.0`, `SWIFT_VERSION = 6.0`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_FILE = Support/Info.plist`, `INFOPLIST_KEY_NSPrincipalClass = NSApplication`, `INFOPLIST_KEY_CFBundleDisplayName = Brow`, `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`, `ENABLE_HARDENED_RUNTIME = NO`, `ENABLE_APP_SANDBOX = NO`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`.

`Support/Info.plist` holds only `NSAppTransportSecurity` with `NSAllowsArbitraryLoadsInWebContent = true`. Without it, `http://` sites, including `localhost`, don't load in the web view.

The shared scheme `Brow` builds and runs the `Brow` target.

- [ ] **Step 2: Build the app UI**

- `main.swift` creates `NSApplication.shared`, sets an `AppDelegate`, and calls `run()`.
- `AppDelegate` creates one `WebKitEngine()` with persistent storage, installs the main menu, and opens a window on launch, on File > New Window, and when the Dock icon is clicked with no windows open. The app keeps running when its last window closes.
- `MainMenu` builds menus in code:
  - App: About, Hide, Quit.
  - File: New Tab (Cmd+T), New Window (Cmd+N), Open Location (Cmd+L), Close Tab (Cmd+W).
  - Edit: the standard Undo, Redo, Cut, Copy, Paste and Select All items wired to the first responder, so copy and paste work in web pages.
  - View: Reload (Cmd+R), Stop (Cmd+.), Back (Cmd+[), Forward (Cmd+]).
  - Window: Minimize, Zoom, Next Tab (Ctrl+Tab), Previous Tab (Ctrl+Shift+Tab), and Cmd+1 to Cmd+9 using `select(number:)`.
- `BrowserWindowController` owns one `BrowserWindowModel` and a split view: `TabListViewController` on the left (220 points wide) and `WebContentViewController` on the right. Its toolbar has back, forward, reload or stop, and an address field.
  - The address field shows the selected tab's URL and selects all of its text when focused.
  - Return runs `AddressInput.resolve`. When there's no selected tab, it opens a tab for the result.
  - New Tab opens a blank tab and focuses the address field. Closing the last tab leaves an empty window. Cmd+W with no tabs closes the window.
  - The window title is `displayTitle` of the selected tab.
- `TabListViewController` is a plain one-column `NSTableView` showing `displayTitle` for each tab, with the selected row matching `selectedTabID`. It's temporary until the sidebar plan.
- `WebContentViewController` shows the selected tab's `contentView`, filling the area, and swaps it when the selection changes.
- `DialogPresenter` watches `dialogForSelectedTab` and shows an `NSAlert` sheet: OK for alerts, OK and Cancel for confirms, and a text field for prompts, filled with `defaultText`. It calls `resolveDialog` with the answer.
- `ObservationLoop` provides `func observe(_ body: @escaping @MainActor () -> Void)`. It runs `body` inside `withObservationTracking` and runs it again on the main actor after each change. All views update through it.

- [ ] **Step 3: Build**

Run: `xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode build`
Expected: `** BUILD SUCCEEDED **` with no warnings from Brow's own files.

- [ ] **Step 4: Check it by hand**

Run: `open .build/xcode/Build/Products/Debug/Brow.app`, then confirm each of these:

1. Typing `apple.com`, then `what is swift`, goes to the site, then a Google search.
2. Signing in to google.com with "Sign in with Google" on a third-party site opens a popup tab that closes itself and leaves you signed in.
3. A YouTube video plays with sound and goes full screen.
4. Cmd+click on a link opens a background tab. Cmd+W closes the selected tab and selects the right neighbour.
5. `http://localhost:<port>` loads from a local server, for example `python3 -m http.server 8000`.

Quit and reopen Brow. You're still signed in to Google.

- [ ] **Step 5: Update the README**

Add `BrowserEngine`, `FakeEngine`, `WebKitEngine` and `Browsing` to the module list, plus `app/Brow` and `app/Brow.xcodeproj` to the folder layout. Add a "Running Brow" section with the build and `open` commands from Steps 3 and 4. Say that Brow runs on WebKit for now, so Chrome extensions don't work yet.

- [ ] **Step 6: Commit**

```bash
git add app README.md
git commit -m "Add Brow app with a WebKit browser window"
```
