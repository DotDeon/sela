<img src="assets/icon.svg" width="64" height="64" alt="">

# Brow

Brow is an open-source Mac browser built to work like Arc: favourites at the top of a sidebar, pinned tabs and folders, unpinned tabs that archive themselves, and spaces you swipe between. It runs on WebKit, the engine Safari uses, with a native Swift interface on top. The design lives in [`docs/design/2026-10-23-brow-design.md`](docs/design/2026-10-23-brow-design.md).

Brow is early. Today it browses websites with Arc's sidebar: favourites, pinned tabs and folders, unpinned tabs, and spaces you swipe between. Cmd+T opens the command bar, and unpinned tabs archive themselves after 12 hours. Split view shows up to four tabs side by side, and links from pinned tabs and favourites to other sites open in Peek, a preview over the page. It blocks ads and trackers with EasyList and EasyPrivacy, and you can turn blocking off for any site. Tabs you haven't looked at for 15 minutes go to sleep to save memory, and wake where they were. On first launch it offers to bring in your Arc sidebar. The repository also holds a tool that backs up your Arc data.

## Folder layout

```
assets/        Brow's own icons and artwork
docs/design/   design documents
docs/plans/    implementation plans
app/Brow/      the Mac app: windows, menus and first-launch import
app/Brow.xcodeproj  Xcode project that builds Brow.app
app/Support/   the app's Info.plist
app/Packages/  Swift package with one module per feature
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
- `Archive`: closed and inactive unpinned tabs, kept 30 days so they can be found and reopened
- `History`: pages you've visited, kept 90 days in a SQLite file on your Mac
- `CommandBar`: the Cmd+T and Cmd+L command bar: ranking and the panel
- `ContentBlocking`: ad and tracker blocking: downloads the filter lists, converts them with AdGuard's converter, and keeps the per-site settings
- `BrowTestSupport`: sample sidebars shared by the tests

## Download

Signed and notarized builds are on the [releases page](https://github.com/DotDeon/brow/releases). Brow needs macOS 15 or later.

## Running Brow

You need Xcode 27.

```bash
xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Debug -derivedDataPath .build/xcode -skipPackagePluginValidation build
open .build/xcode/Build/Products/Debug/Brow.app
```

`-skipPackagePluginValidation` lets AdGuard's SafariConverterLib run its build plugin, which only writes the library's version number into its source.

Brow is signed ad hoc by default. To sign it with your own Apple team, copy `app/Support/Signing.local.xcconfig.example` to `app/Support/Signing.local.xcconfig` and fill in your team ID and profile name. Git ignores that file.

You can also open `app/Brow.xcodeproj` in Xcode and press Cmd+R. The first time, Xcode asks you to trust the `GenerateVersion` plugin from `safariconverterlib`.

To measure how much memory Brow uses with 10 real sites open, before and after tabs sleep, quit Brow, Safari and Mail and run `scripts/measure-memory.sh`. It uses a throwaway profile, so your sidebar isn't touched.

To build a signed, notarized release zip, run `scripts/release.sh TEAM_ID`. It needs a Developer ID Application certificate and the `asc` command-line tool logged in to App Store Connect.

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

## Licence

Brow is free software under the GNU General Public License, version 3. See [`LICENSE`](LICENSE).

## Third-party code

- [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) by AdGuard (GPL-3.0) converts ad blocking filter lists into WebKit's content blocking rules.
- [@adguard/safari-extension](https://github.com/AdguardTeam/SafariConverterLib/tree/master/Extension), [@adguard/extended-css](https://github.com/AdguardTeam/ExtendedCss) and [@adguard/scriptlets](https://github.com/AdguardTeam/Scriptlets) by AdGuard (GPL-3.0) apply the rules WebKit can't, inside each page.
- [PunycodeSwift](https://github.com/gumob/PunycodeSwift) (MIT) and [swift-psl](https://github.com/ameshkov/swift-psl) (MIT) come with SafariConverterLib.
- [EasyList and EasyPrivacy](https://easylist.to) (GPL-3.0 or CC BY-SA 3.0) are downloaded at run time, not shipped with Brow.
