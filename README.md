<img src="assets/icon.svg" width="64" height="64" alt="">

# Brow

Brow is an open-source Mac browser built to work like Arc: favourites at the top of a sidebar, pinned tabs and folders, unpinned tabs that archive themselves, and spaces you swipe between. It runs on Chromium so Chrome extensions work, with a native Swift interface on top. The design lives in [`docs/design/2026-10-23-brow-design.md`](docs/design/2026-10-23-brow-design.md).

Brow is early. Today it browses websites with Arc's sidebar: favourites, pinned tabs and folders, unpinned tabs, and spaces you swipe between. On first launch it offers to bring in your Arc sidebar. The repository also holds a tool that backs up your Arc data. It runs on WebKit for now, so Chrome extensions don't work yet. Chromium replaces WebKit once Brow's Chromium build is ready.

## Folder layout

```
assets/        Brow's own icons and artwork
docs/design/   design documents
docs/plans/    implementation plans
app/Brow/      the Mac app: windows, menus and first-launch import
app/Brow.xcodeproj  Xcode project that builds Brow.app
app/Support/   the app's Info.plist
app/Packages/  Swift package with one module per feature
chromium/      Chromium patches and Brow's C++ code (coming later)
scripts/       build, sign and release scripts (coming later)
```

Inside `app/Packages`:

- `SidebarModel`: spaces, tabs, folders and favourites, and how they're saved to disk
- `ArcImport`: reads Arc's `StorableSidebar.json` into Brow's sidebar
- `ArcSnapshot`: copies Arc's data folder, minus caches, so it survives Arc shutting down
- `brow-arc`: command-line tool for the two above
- `BrowserEngine`: the protocols Brow's UI uses to talk to a browser engine
- `WebKitEngine`: those protocols built on Safari's WebKit
- `FakeEngine`: a stand-in engine with no web content, for tests
- `Browsing`: a window's live tabs on top of the sidebar, popups, page dialogs, and address bar parsing
- `Sidebar`: the shared sidebar store that saves itself, plus outline, drag and drop, and swipe logic
- `SidebarUI`: the sidebar's views: favourites grid, space pages, space bar and address
- `Favicons`: site icons, fetched from each site and cached on disk
- `BrowTestSupport`: sample sidebars shared by the tests

## Running Brow

You need Xcode 27.

```bash
xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/Brow.app
```

You can also open `app/Brow.xcodeproj` in Xcode and press Cmd+R.

## Running the tests

```bash
swift test --package-path app/Packages
```

## Backing up and checking your Arc data

Quit Arc, then copy its data to a folder of your choice, ideally an external drive:

```bash
swift run --package-path app/Packages brow-arc snapshot "/Volumes/Backup"
```

This creates a folder named `Arc-snapshot-<date>`. It refuses to run while Arc is open, because copying Arc's databases while Arc writes to them gives a broken copy.

The snapshot can't recover your saved passwords on another Mac, because Arc encrypts them with a key that stays in this Mac's keychain. Export your passwords to a CSV file from Arc's password settings before Arc shuts down.

To see what Brow would import from your live Arc data or from a snapshot:

```bash
swift run --package-path app/Packages brow-arc inspect
swift run --package-path app/Packages brow-arc inspect --root "/Volumes/Backup/Arc-snapshot-<date>"
```

Neither command changes anything in Arc's folder.
