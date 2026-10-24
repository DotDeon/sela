# Browser essentials implementation plan

Steps use checkbox (`- [ ]`) syntax for tracking. Work through the tasks in order.

**Goal:** The everyday things any browser does: choosing files for upload, downloading files, find in page (Cmd+F), and asking before a site uses the camera or microphone.

**Architecture:**
- **The engine reports, the window decides.** `BrowserTabDelegate` gains three requests: pick files, where to save a download, and permission for media capture. `BrowserTab` gains `find`.
- **New module `Downloads`:** an observable list of downloads in this session, plus the file-naming rule.
- **Permissions:** the decisions live in `Browsing` as `SitePermissions`, backed by `UserDefaults`.
- **The app:** shows the open panel, the find bar, a downloads popover and the permission prompts.

**Tech stack:** Swift 6, SwiftPM, Swift Testing, AppKit, WebKit (only in `WebKitEngine`), `WKDownload`.

**Spec:** `docs/design/2026-10-23-brow-design.md`, milestone 6, "Browser essentials". This plan covers downloads, find in page and permissions. Arc history import and settings come in the next plan.

## Global constraints

- Everything from earlier plans applies:
  - No AI tool mentions in the repository.
  - No WebKit import outside `WebKitEngine`.
  - Every `xcodebuild` command uses `-skipPackagePluginValidation`.
- Downloads go to the user's Downloads folder, `FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)`.
  - A name already taken gets ` 2`, ` 3` and so on before the extension, as Safari does: `report.pdf` becomes `report 2.pdf`.
  - A download in progress is written as `<name>.download` and renamed when it finishes.
- Find in page: Cmd+F opens the bar, Return or Cmd+G finds the next match, Shift+Return or Cmd+Shift+G finds the previous one, and Escape closes the bar. The search ignores case and wraps around.
- Camera and microphone:
  - Brow asks once per site, as `contentBlockingSite` names it, and remembers "Allow" or "Don't Allow" in `UserDefaults` key `SitePermissions`.
  - `Info.plist` gains `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`.
  - Release builds sign with the hardened runtime entitlements `com.apple.security.device.camera` and `com.apple.security.device.audio-input`, in `app/Support/Brow.entitlements`.
- Choosing files uses `NSOpenPanel` as a sheet on the window, respecting the page's multiple-files and folder settings.

## Review focus

1. **A download whose name is taken twice over.** `report.pdf`, `report 2.pdf` and `report 3.pdf` all exist, so the next one is `report 4.pdf`, and nothing is overwritten. (Task 2)
2. **Quitting mid-download.** The partial `.download` file is removed, not left looking like a finished file. (Task 2)
3. **A site asking for camera and microphone together.** One prompt covers both, and the answer covers both. (Task 3)
4. **Find on a page with no match.** The bar says "Not found" and doesn't scroll. (Task 1)
5. **Upload from a background tab or Peek.** The open panel appears over the right window, and cancelling sends an empty choice back to the page. (Task 1)

---

### Task 1: Engine requests: files, find and permissions

**Files:**
- Modify: `app/Packages/Sources/BrowserEngine/BrowserTab.swift`, `BrowserTabDelegate.swift`
- Create: `app/Packages/Sources/BrowserEngine/MediaCapture.swift`
- Modify: `app/Packages/Sources/WebKitEngine/WebKitTab.swift`, `app/Packages/Sources/FakeEngine/FakeTab.swift`
- Test: `app/Packages/Tests/EngineContractTests/EssentialsContractTests.swift`, `app/Packages/Tests/FakeEngineTests/FakeTabTests.swift`

**Interfaces:**
- Produces:
  - `public enum MediaCapture: Sendable, Equatable { case camera, microphone, cameraAndMicrophone }`
  - On `BrowserTabDelegate`, each with a default in a protocol extension:
    - `func tab(_ tab: any BrowserTab, chooseFiles allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]?`, defaulting to nil
    - `func tab(_ tab: any BrowserTab, mayCapture media: MediaCapture, forOrigin origin: URL) async -> Bool`, defaulting to false
  - On `BrowserTab`: `func find(_ text: String, backwards: Bool) async -> Bool` returns whether there was a match. `func clearFind()` removes the highlight.
  - `FakeTab` hooks:
    - `public var findResult = false` and `public private(set) var finds: [(String, Bool)]`
    - `simulateChooseFiles(multiple:directories:) async -> [URL]?`
    - `simulateCaptureRequest(_:origin:) async -> Bool`

- [ ] **Step 1: Failing tests**
  - `findMatchesTextOnThePage` (contract): page `<p>Hello there</p>`. Expect `await tab.find("there", backwards: false) == true` and `await tab.find("absent", backwards: false) == false`.
  - `findIgnoresCase` (contract): expect `await tab.find("HELLO", backwards: false) == true`.
  - Fake tests: the hooks pass the request through to the delegate and return its answer, and a delegate that doesn't implement them gets the defaults (nil and false).

- [ ] **Step 2: Run them and see them fail, then implement**

Run: `swift test --filter "EssentialsContractTests|FakeTabTests"`
Expected: compile errors, then passes.

- **`find`:** uses `WKFindConfiguration`, with `caseSensitive = false`, `wraps = true` and `backwards` as given. It returns `WKFindResult.matchFound`.
- **`clearFind`:** selects nothing with `evaluateJavaScript("window.getSelection().removeAllRanges()")`.
- **Choosing files:** `WKUIDelegate.runOpenPanelWith` maps `parameters.allowsMultipleSelection` and `allowsDirectories` to the delegate. Nil from the delegate means cancel.
- **Camera and microphone:** `requestMediaCapturePermissionFor` maps `.camera`, `.microphone` and `.cameraAndMicrophone` to `MediaCapture`, passing the origin as a URL built from `origin.protocol://origin.host[:port]`. It answers `.grant` or `.deny`.

- [ ] **Step 3: Run the suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git commit -am "Let pages ask for files, find text and request the camera or microphone"
```

---

### Task 2: Downloads

**Files:**
- Create: `app/Packages/Sources/Downloads/DownloadNaming.swift`, `DownloadList.swift`
- Create: `app/Packages/Sources/BrowserEngine/BrowserDownload.swift`
- Modify: `BrowserTabDelegate.swift`, `WebKitTab.swift`, `FakeTab.swift`, `app/Packages/Package.swift`, `app/Brow.xcodeproj/project.pbxproj` (a `Downloads` product, ID `B7000000000000000000002A` for the build file and `B7000000000000000000002B` for the product)
- Test: `app/Packages/Tests/DownloadsTests/DownloadNamingTests.swift`, `DownloadListTests.swift`, `app/Packages/Tests/EngineContractTests/EssentialsContractTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor public protocol BrowserDownload: AnyObject, Observable`, with:
    - `var id: UUID { get }`
    - `var filename: String { get }`
    - `var progress: Double { get }`, from 0 to 1, or -1 when the size is unknown
    - `var state: DownloadState { get }`
    - `func cancel()`
  - `public enum DownloadState: Equatable, Sendable { case downloading, finished(URL), failed(String), cancelled }`
  - `BrowserTabDelegate.tab(_:, didStartDownload download: any BrowserDownload, suggestedFilename: String) async -> URL?` returns where to write, or nil to refuse. The default is nil.
  - `Downloads`:
    - `public func availableDestination(for filename: String, in folder: URL, fileExists: (URL) -> Bool) -> URL`
    - `@MainActor @Observable public final class DownloadList { public private(set) var downloads: [any BrowserDownload]; public func add(_:); public func clearFinished() }`, newest first
    - `public func partialURL(for destination: URL) -> URL`, which appends `.download`

- [ ] **Step 1: Failing tests**
  - `takenNamesGetANumber`
    - Do: run `availableDestination` with existing `report.pdf`, `report 2.pdf` and `report 3.pdf`.
    - Expect: `report 4.pdf`.
  - `namesWithoutExtensions`
    - Do: run it for `README` with `README` taken.
    - Expect: `README 2`.
  - `unsafeNamesAreCleaned`
    - Do: run it for `../../etc/passwd` and an empty name.
    - Expect: `passwd` and `download`.
  - `listKeepsNewestFirst` and `clearFinishedKeepsActiveOnes`, using a small fake download.
  - `downloadsArriveWhereTheDelegateSays` (contract)
    - Do: the page `<a id="d" href="data.txt" download>get</a>` clicks the link from its own script after 200 ms. The delegate returns a path in a temporary folder.
    - Expect: the file is there with the right contents, and `state` is `.finished` with that URL.

- [ ] **Step 2: Run them and see them fail, then implement**

Run: `swift test --filter "DownloadsTests|downloadsArriveWhereTheDelegateSays"`
Expected: compile errors, then passes.

- **Starting a download:** `WebKitTab` turns navigations into downloads when either:
  - the action has `shouldPerformDownload`, or
  - the response can't be shown (`!navigationResponse.canShowMIMEType`) or has `Content-Disposition: attachment`.
- **`WebKitDownload`:** wraps `WKDownload` as a `WKDownloadDelegate`. It asks the tab's delegate for the destination and writes to `partialURL(for:)`, then renames on finish. On failure or cancel it removes the partial file. Progress comes from `download.progress.fractionCompleted`.

- [ ] **Step 3: Run the suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git commit -am "Download files to the Downloads folder"
```

---

### Task 3: Site permissions

**Files:**
- Create: `app/Packages/Sources/Browsing/SitePermissions.swift`
- Test: `app/Packages/Tests/BrowsingTests/SitePermissionsTests.swift`

**Interfaces:**
- Produces:
  - `public struct SitePermissions { public init(defaults: UserDefaults = .standard) }`, with:
    - `public func decision(for media: MediaCapture, on origin: URL) -> Bool?` returns nil when the user hasn't been asked yet.
    - `public func remember(_ allowed: Bool, for media: MediaCapture, on origin: URL)`
    - `public func forget(siteOf origin: URL)`
  - Both camera and microphone are stored per site. `.cameraAndMicrophone` counts as allowed only when both are allowed, and remembering it sets both.
  - Sites are keyed with `siteKey(forHost:)`.

- [ ] **Step 1: Failing tests**
  - `unknownUntilRemembered`
  - `rememberedPerSite`: remembering for `https://meet.google.com` gives the same answer for `https://accounts.google.com`, but not for `https://example.com`.
  - `bothNeedsBoth`: allowing only the camera leaves `.cameraAndMicrophone` as nil, because the microphone was never asked.
  - `forgetClears`

- [ ] **Step 2: Run them, see them fail, implement, see them pass, commit**

Run: `swift test --filter SitePermissionsTests`
Expected: fail, then pass.

```bash
git commit -am "Remember camera and microphone choices per site"
```

---

### Task 4: The app: open panel, find bar, downloads and prompts

**Files:**
- Create: `app/Brow/FindBarController.swift`, `app/Brow/DownloadsPopover.swift`, `app/Support/Brow.entitlements`
- Modify: `app/Packages/Sources/Browsing/BrowserWindowModel.swift`, which forwards the three delegate requests to closures the app sets:
  - `onChooseFiles`
  - `onDownloadDestination`
  - `onCaptureRequest`
- Modify: `app/Brow/BrowserWindowController.swift`, `BrowserRootViewController.swift`, `MainMenu.swift`, `AppDelegate.swift`, `app/Support/Info.plist`, `scripts/release.sh` (`CODE_SIGN_ENTITLEMENTS=app/Support/Brow.entitlements`), `README.md`

- [ ] **Step 1: Model forwarding (with tests)**

Add these tests to `BrowserWindowModelTests`:
- `fileChoicesGoThroughTheWindow`: a `FakeTab`'s `simulateChooseFiles` reaches `onChooseFiles` and returns its answer.
- `captureRequestsUseRememberedChoices`: with a remembered "allow" for the site, `onCaptureRequest` isn't called and the answer is true.
- `downloadsAreListed`: a started download appears in `model.downloads`, which is the shared `DownloadList` passed into `init`.

Then run `swift test` and confirm they fail, implement them, and confirm they pass.

- [ ] **Step 2: App pieces (no app-target tests)**
- **Open panel:** an `NSOpenPanel` sheet on the tab's window.
- **Find bar:**
  - It appears at the top right of the page card: a text field, previous and next buttons, and "Not found" when there's no match.
  - It's opened with Edit > Find > Find… (Cmd+F). Find Next (Cmd+G) and Find Previous (Cmd+Shift+G) are menu items.
  - Escape closes it and clears the highlight.
- **Downloads popover:**
  - A download button appears in the sidebar's bottom bar while the session has downloads.
  - The popover lists each download's name, progress, Show in Finder and Cancel, plus "Clear".
  - A new download opens it briefly.
- **Camera and microphone prompt:** an `NSAlert` sheet, "Allow ‹site› to use your camera and microphone?", with "Allow" and "Don't Allow". The answer is remembered.
- **`Info.plist` usage strings:** "Websites you allow can use your camera." and "Websites you allow can use your microphone."
- **`Brow.entitlements`:** holds the two device entitlements. `release.sh` passes it.

- [ ] **Step 3: Build, check by hand, commit**

Run: `swift test` and the `xcodebuild` Debug build.
Expected: all tests pass and `BUILD SUCCEEDED`. The owner checks four things by hand:
1. Cmd+F on a long page.
2. Downloading a PDF.
3. Uploading a photo.
4. A camera test site such as webcamtests.com.

```bash
git commit -am "Add the find bar, downloads, file uploads and camera prompts to Brow"
```
