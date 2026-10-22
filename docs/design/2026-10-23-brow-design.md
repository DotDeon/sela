# Brow design

Status: draft, 2026-10-23

## Why Brow exists

The Browser Company is shutting down Arc in December 2026. Brow is an open-source replacement for people who live in Arc and don't want to give up how it works. The owner uses Arc every day and has tried the vertical tab and sidebar options in other browsers. None of them feel the same.

Success means the owner switches from Arc to Brow on their new Mac and doesn't miss Arc. Other Arc users can do the same by downloading Brow and importing their Arc setup.

## What makes Arc's sidebar different

All five of these are required. Together they are the product.

1. **Favourites.** A grid of site icons at the top of the sidebar, shared across every space.
2. **Pinned tabs and folders.** Pinned tabs act like bookmarks that open as live tabs. Folders nest and collapse. A pinned tab remembers its saved URL and can be reset to it after you navigate away.
3. **Unpinned tabs archive themselves.** Tabs below the pinned section close automatically after a period of inactivity (Arc's default is 12 hours) and move to a searchable archive.
4. **Spaces.** Each space has its own colour theme, pinned tabs and unpinned tabs. You swipe between spaces with two fingers on the trackpad, and the sidebar pages across like a native scroll view.
5. **The feel.** Smooth animations, drag and drop for everything in the sidebar, and a sidebar that can hide and then slide out when the pointer reaches the window edge.

## Goals for the first version

- The sidebar exactly as described above.
- **Command bar.** Cmd+T opens one search box that finds open tabs, pinned tabs, history and web results, and runs commands.
- **Split view.** Two or more tabs side by side in one window.
- **Peek.** Links opened from a pinned tab show in a preview window over the current page, which can be expanded into a full tab.
- **Full Chrome extension support.** Any extension from the Chrome Web Store installs and works, including toolbar popups and password managers.
- **Import from Arc on first launch.** Spaces, pinned tabs, folders, favourites, history, passwords and extensions come across, so switching takes seconds.
- **iCloud sync.** Spaces, pinned tabs, folders and favourites sync across the user's Macs through CloudKit. Sync is built last in the first version. Brow must be fully usable on one Mac without it.
- **Signed, notarized and self-updating.** Users download a DMG that opens without a Gatekeeper warning, and Brow updates itself.

## Non-goals

- **Little Arc** (the small floating window for links from other apps). Maybe later, not in the first version.
- **Windows and Linux.** Brow is Mac-only because the UI is native AppKit.
- **A phone app** or anything like Arc Search.
- **Chrome Sync.** Google blocks third-party Chromium builds from its sync servers. History and passwords don't sync between Macs. Password manager extensions cover passwords.
- **AI features** like Ask Arc, tab tidying or page summaries.
- **Spaces on separate profiles.** Arc lets each space use its own profile. The owner's three spaces all use the default profile, so the first version uses one profile for every space. The data model keeps the profile field so this can come later.

## Anti-goals

These would make Brow a failure even if it technically works.

- **Boosts.** No custom CSS or JS site restyling, ever.
- **A web-drawn browser UI.** If the sidebar is HTML inside Chromium, it won't feel like Arc. The browser UI must be native.
- **Running a server.** Brow must never need a backend operated by the project. No accounts and no hosting bills that grow with users.
- **Telemetry.** No analytics, usage statistics or crash uploads. Chromium's Google services that make the browser work stay on: Safe Browsing, the Chrome Web Store, extension and component updates, and spellcheck. Chrome's usage statistics and crash reporting stay off.
- **Copying Arc.** No Arc code, icons, sounds, animation files, fonts or other assets go into Brow. Brow behaves like Arc but everything in it is written or drawn from scratch. "Arc" appears only where Brow names the browser it imports from.

## Constraints

- **Hardware.** Chromium needs roughly 100 to 150 GB of disk and benefits from 32 GB of RAM or more. The owner's current Mac can't build it. Building starts when their new Mac arrives, around late November 2026. Planning and anything that doesn't need a Chromium build can happen before then.
- **Chromium cadence.** Chrome ships a new major version every 4 weeks. Brow must be able to follow within days, not weeks.
- **Apple Developer Program.** The project needs a paid membership ($99 a year) for code signing, notarization and the CloudKit container.
- **The repository never mentions the AI tools used to build it.** That covers commit messages, trailers, PR descriptions, file names, comments and docs. Don't commit agent config files or folders.
- **Clean file structure.** Each folder has one clear purpose, documented in the README.

## How Arc is built

A static teardown of Arc 1.169.0 (built 14 October 2026) shaped the decisions below. These findings come from symbols, strings and bundle layout, not from decompiling or running Arc.

- `Arc.app/Contents/MacOS/Arc` is a 166 MB universal Swift binary using AppKit and SwiftUI.
- `ArcCore.framework` is Chromium 155.0.8059.80 built as a framework, with Chrome-style helper apps for renderer and GPU processes.
- ArcCore exports 259 symbols, 251 of them Objective-C classes (`ArcBrowser`, `ArcWebContents`, `ArcBrowserContextExtensions`, `ArcExtensionToolbarAction` and so on). The Swift app never calls Chromium's C++ directly.
- The sidebar is native AppKit. Each item is a row in a table view (`SidebarViewController`, `SidebarTableRowView`, `SidebarItemView`). Spaces are pages in a paging scroll view (`SidebarPagingContainerScrollView`). Smaller panels like space creation are SwiftUI hosted in AppKit.
- App state uses The Composable Architecture with about 85 feature modules and 60 dependency clients.
- Sparkle handles updates. Sidebar sync started on CloudKit and later moved to Firebase.

## Architecture

Brow copies Arc's structure: a Chromium framework with a small Objective-C bridge, and a native Swift app on top.

### BrowCore

BrowCore is Chromium with Chrome's browser layer (`//chrome`) kept intact, so extensions, the password manager, profiles, downloads, history, permissions and `chrome://` settings pages all keep working. On macOS, Chrome already ships almost everything inside `Google Chrome Framework.framework`, and the app bundle is a thin shell around it. BrowCore keeps that framework and replaces the shell.

- Brow's own C++ and Objective-C++ code lives in a new top-level directory in the Chromium tree, `//brow`. It's added to the build with a minimal patch so most of Brow's code never conflicts with upstream.
- `//brow/bridge` exposes an Objective-C API to Swift. The first version needs roughly 20 to 30 classes covering: application startup, profiles, windows, tabs and their web content views, navigation and back/forward lists, find in page, extensions (list, toolbar actions, popups, permissions), downloads, history queries, autocomplete for the command bar, context menus, permission prompts, JavaScript dialogs and the import pipeline.
- Chrome's own browser window UI (`BrowserView` and its toolbar, tab strip and omnibox) is never shown. Brow draws all browser UI itself.

**The hardest technical risk.** Chrome's extension APIs (`chrome.tabs`, `chrome.windows`, action popups, content script injection rules) assume every tab belongs to a Chrome `Browser` object with a `TabStripModel`. The expected approach is to keep a real `Browser` and `TabStripModel` behind each Brow window, mirror Brow's tabs into it, keep Chrome's `BrowserView` hidden, and show each tab's web contents inside Brow's own views. Arc's `ArcBrowser` class suggests Arc did something similar. This must be proven in the first spike before anything else gets built on it.

If the spike shows Chrome's window can't be fully hidden behind Brow's UI, the fallback is to accept extensions that mostly work, with some quirks around tab and window APIs. Popups, password managers and content blockers are the must-haves. Showing Chrome's own UI is not an acceptable fallback.

### Patch stack

Changes to existing Chromium files live as an ordered series of patch files in `chromium/patches/`, applied to a pinned upstream Chromium tag. The pin lives in `chromium/VERSION`. Scripts fetch Chromium, apply the patches, and help rebase them on a new tag. Brave and ungoogled-chromium are the reference for how this works in practice. The goal is to keep patches to existing upstream files small and few, and to put everything possible in `//brow`.

Branding (name, icons, bundle identifiers, user data directory, update URLs) is applied through Chromium's existing branding build files, not by editing strings throughout the tree.

### The Brow app

- Swift, with the sidebar, command bar, split view and Peek in AppKit, and smaller panels and settings screens in SwiftUI hosted inside AppKit. This matches how Arc gets its feel: table view rows for sidebar items and native drag and drop.
- Feature code lives in Swift packages, one module per feature, so features stay isolated and each can be tested without a Chromium build.
- The UI never talks to a browser engine directly. It talks to the engine protocols described below.

### Browser engines

Brow's UI depends only on a set of Swift protocols in the `BrowserEngine` module: create and close tabs, show a tab's content view, navigate, observe title, URL, favicon, loading and audio state, back/forward, find in page, handle new-window requests, downloads, permission prompts and JavaScript dialogs. Three implementations sit behind them:

1. **`WebKitEngine`, first.** Built on `WKWebView`, which ships with macOS. It lets Brow load real websites on the owner's current Mac, so Brow becomes usable before the Chromium build exists.
2. **`ChromiumEngine`, later.** Built on BrowCore's Objective-C bridge once the new Mac arrives. It becomes the default engine and brings Chrome extensions, Chrome's password manager, history import and `chrome://` pages.
3. **`FakeEngine`, for tests and previews only.** No web content.

Rules that keep the swap cheap:

- No WebKit or Chromium type appears in a protocol or in any feature module. Only `BrowserEngine` implementations import `WebKit` or BrowCore.
- Engine-specific capabilities (extensions, `chrome://` pages, profile import) are optional protocol members the UI checks for. With WebKit they're absent and the UI hides them. It doesn't fake them.
- Each engine keeps its own cookies and site data. Switching engines means signing in to websites again once, which is acceptable.
- The same protocol test suite runs against every engine that's available on the machine.

### Sidebar data model

Brow uses the same shape Arc uses, because it's proven and makes import a straight mapping.

- A flat list of items, each with `id`, `parentID`, `childrenIds`, `title`, `createdAt`, and a `data` payload that is one of:
  - `tab`: saved URL, saved title, last active time, mute status
  - `list`: a folder, with an optional custom icon
  - `itemContainer`: the root container for a space's pinned items, unpinned items, or the favourites grid
- Spaces reference their containers, a colour theme, an icon and a profile.
- An ordered list of space IDs and the favourites container ID sit at the top level.
- The whole sidebar is stored as one JSON file in Brow's Application Support folder, written atomically. Archived tabs go in a separate JSON file, like Arc's `StorableArchive`.

### Import from Arc

Arc stores its sidebar in `~/Library/Application Support/Arc/StorableSidebar.json`. Its top level has `sidebar.containers`, where the second container holds `items`, `spaces` and `topAppsContainerIDs`. Item and space shapes match the model above. The importer reads this file read-only and builds Brow's sidebar from it.

History, passwords, cookies and autofill come from Arc's Chromium profile in `~/Library/Application Support/Arc/User Data/`, using Chromium's existing importer code where possible. Arc must be closed during import because its profile databases are locked while it runs. Arc encrypts saved passwords and cookies with a key in the macOS keychain ("Arc Safe Storage"), so the importer asks the user to allow keychain access once.

Extensions are reinstalled from the Chrome Web Store using the extension IDs in Arc's profile, not copied with their data. Users sign in to each extension again. Copying extension storage across browsers is fragile and not worth the risk in the first version.

**Arc snapshot tool.** Nobody knows whether Arc keeps launching, or keeps its data, after the December shutdown. A small standalone tool copies Arc's Application Support folder to a safe location, and the importer reads from either the live Arc folder or a snapshot. This tool needs no Chromium build, so it gets built first, before the new Mac arrives, and the owner runs it before December.

### Sync

CloudKit private database, one record per sidebar item and space, with each user's data in their own iCloud account. Arc's earlier CloudKit sync stored per-item records plus an ordered space list and a container record, which is the model to follow. Conflicts resolve per item, last write wins, with deletions tracked so a deleted item can't come back from a stale device.

## Repository layout

```
brow/
  README.md              what Brow is, how to build it, what each folder holds
  LICENSE
  assets/                Brow's own icons and artwork
  docs/
    design/              design documents like this one
    building.md          machine requirements, fetching Chromium, building, signing
    updating-chromium.md how to move the patch stack to a new Chromium tag
  chromium/
    VERSION              pinned upstream Chromium tag
    patches/             ordered patch series against upstream files
    brow/                Brow's C++ and Objective-C++ code, linked in as //brow
      bridge/            Objective-C API exposed to Swift
      browser/           Brow-specific browser-layer code
      branding/          name, icons, identifiers
  app/
    Brow.xcodeproj       the macOS app target
    Brow/                app entry point, window management, menus
    Packages/            one Swift package per feature: Sidebar, Spaces,
                         CommandBar, SplitView, Peek, Archive, ArcImport,
                         Sync, Settings, BrowserEngine (engine protocols),
                         WebKitEngine, ChromiumEngine, FakeEngine
  scripts/               fetch, patch, build, sign, notarize, release
  .github/workflows/     CI for the Swift app and patch-stack checks
```

The Chromium checkout itself lives outside the repository (for example `~/chromium/src`) and is never committed.

## Decisions

Made by the owner:

- Chromium fork for full Chrome extension support.
- Native Mac UI in Swift and AppKit, built on an Objective-C bridge like Arc. Not web-drawn.
- Mac only.
- First version: sidebar, command bar, split view, Peek, Arc import, CloudKit sync. Little Arc later. Boosts never.
- CloudKit for sync.
- If the native-window spike fails, accept extensions with some quirks rather than showing Chrome's UI.
- Development runs close to full time from when the new Mac arrives, with the owner testing builds and judging the feel.

Made as calls during design. The owner can override any of these:

- Sync is built last in the first version.
- The JSON storage format mirrors Arc's.
- Sparkle for self-updates, as Arc uses. Release builds and the update feed are hosted on GitHub Releases, which keeps Brow free of a server.
- No crash reporting service by default.
- Track Chrome's stable channel.
- Keep Chromium's Google services that make the browser work, and turn off usage statistics and crash uploads. Get Google API keys for Brow under Google's terms for Chromium-based browsers.
- Apply for Widevine early, since Netflix, Spotify and other DRM video and music sites won't play without it and approval can take weeks.
- One profile for all spaces in the first version.
- Extensions are reinstalled from the Web Store during import, not copied.
- WebKit is the first engine so Brow is usable on the owner's current Mac. Chromium replaces it as the default when BrowCore is ready. (Owner agreed.)
- Feature state uses Swift's Observation framework (`@Observable` stores per feature) instead of The Composable Architecture. It's simpler for a small team and doesn't fight AppKit.

## Suggested milestones

0. **Arc snapshot tool.** Built and run on the owner's current Mac before December.
1. **Build machine ready.** Fetch and build stock Chromium on the new Mac. Set up the patch tooling and the pinned version.
2. **Spike: Swift app shows a Chromium page.** A minimal Swift window shows one tab from BrowCore, navigates, and opens a Chrome Web Store extension's popup. This proves the bridge and the hidden `Browser` approach.
3. **Tabs, windows and the sidebar.** Spaces, pinned tabs, folders, favourites, unpinned tabs, drag and drop, swipe between spaces, local JSON storage.
4. **Archiving, command bar, split view and Peek.**
5. **Arc import.**
6. **Browser essentials.** Extensions toolbar, downloads, history, find in page, permissions, dialogs, settings through `chrome://settings`.
7. **CloudKit sync.**
8. **Release.** Signing, notarization, Sparkle updates, a public DMG.

The owner's daily-driver cut on Chromium is milestones 1, 2, 3, 5 and the extension parts of 6. Milestone 4 can follow it if time runs short.

### Order before the new Mac arrives

The owner's current Mac (M2, 8 GB RAM) can't build Chromium, but it can build everything on the Swift side. Work starts there, on `WebKitEngine`:

1. Milestone 0, the Arc snapshot tool.
2. The sidebar data model, JSON storage and the Arc sidebar importer, tested against the owner's real `StorableSidebar.json`.
3. The engine protocols, `FakeEngine` and `WebKitEngine`, and a Brow window that browses real websites.
4. The sidebar UI from milestone 3: spaces, pinned tabs, folders, favourites, unpinned tabs, drag and drop, swiping and animations.
5. Archiving, then the command bar, split view and Peek from milestone 4.
6. CloudKit sync from milestone 7.

When the new Mac arrives, milestones 1 and 2 run, `ChromiumEngine` is built behind the same protocols, and it becomes the default.

## Left to the builder

- Exact bridge class names and API shape.
- How the hidden `Browser` and `TabStripModel` are kept in sync with Brow's tabs, once the spike proves it works.
- The archive search UI, the command bar ranking, and keyboard shortcut defaults. These follow Arc's defaults unless there's a reason not to.
- Animation timings and spring curves, tuned by feel against Arc on the owner's Mac.
- CI details.
