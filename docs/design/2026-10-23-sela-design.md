# Sela design

Status: draft, 2026-10-23. The engine changed from a Chromium fork to WebKit for good on 2026-10-23. See Decisions.

## Why Sela exists

The Browser Company is shutting down Arc in December 2026. Sela is an open-source replacement for people who live in Arc and don't want to give up how it works. The owner uses Arc every day and has tried the vertical tab and sidebar options in other browsers. None of them feel the same.

Success means the owner switches from Arc to Sela and doesn't miss Arc. Other Arc users can do the same by downloading Sela and importing their Arc setup.

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
- **WebKit, the engine Safari uses.** It ships with macOS, so Sela has no engine to build, patch or keep up to date.
- **Import from Arc on first launch.** Spaces, pinned tabs, folders, favourites and history come across, so switching takes seconds.
- **iCloud sync.** Spaces, pinned tabs, folders and favourites sync across the user's Macs through CloudKit. Sync is built last in the first version. Sela must be fully usable on one Mac without it.
- **Signed, notarized and self-updating.** Users download a DMG that opens without a Gatekeeper warning, and Sela updates itself.

## Non-goals

- **Little Arc** (the small floating window for links from other apps). Maybe later, not in the first version.
- **Windows and Linux.** Sela is Mac-only because the UI is native AppKit.
- **A phone app** or anything like Arc Search.
- **Chrome extensions.** WebKit can't run them. Password managers work through their own Mac apps instead.
- **A built-in password manager.** Passwords live in the user's password manager or Apple's Passwords app.
- **AI features** like Ask Arc, tab tidying or page summaries.
- **Spaces on separate profiles.** Arc lets each space use its own profile. The owner's three spaces all use the default profile, so the first version uses one profile for every space. The data model keeps the profile field so this can come later.

## Anti-goals

These would make Sela a failure even if it technically works.

- **Boosts.** No custom CSS or JS site restyling, ever.
- **A web-drawn browser UI.** If the sidebar is HTML inside a web view, it won't feel like Arc. The browser UI must be native.
- **Running a server.** Sela must never need a backend operated by the project. No accounts and no hosting bills that grow with users.
- **Telemetry.** No analytics, usage statistics or crash uploads.
- **Copying Arc.** No Arc code, icons, sounds, animation files, fonts or other assets go into Sela. Sela behaves like Arc but everything in it is written or drawn from scratch. "Arc" appears only where Sela names the browser it imports from.

## Constraints

- **WebKit sets the limits.** Web features, video formats and DRM come from the version of WebKit in the user's macOS. Netflix, Spotify and other DRM sites play through Apple's FairPlay.
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

Sela copies the shape of Arc's app: a native Swift app drawing all the browser UI on top of a browser engine. Arc wraps Chromium in its own framework. Sela uses WebKit through `WKWebView`, so there is no engine to build or patch.

### The Sela app

- Swift, with the sidebar, command bar, split view and Peek in AppKit, and smaller panels and settings screens in SwiftUI hosted inside AppKit. This matches how Arc gets its feel: table view rows for sidebar items and native drag and drop.
- Feature code lives in Swift packages, one module per feature, so features stay isolated and each can be tested on its own.
- The UI never talks to a browser engine directly. It talks to the engine protocols described below.

### Browser engines

Sela's UI depends only on a set of Swift protocols in the `BrowserEngine` module: create and close tabs, show a tab's content view, navigate, observe title, URL, favicon, loading and audio state, back/forward, find in page, handle new-window requests, downloads, permission prompts and JavaScript dialogs. Two implementations sit behind them:

1. **`WebKitEngine`.** Built on `WKWebView`, which ships with macOS. The only engine Sela ships.
2. **`FakeEngine`, for tests and previews only.** No web content.

Rules that keep the UI independent of WebKit, so another engine could still be added one day:

- No WebKit type appears in a protocol or in any feature module. Only `WebKitEngine` imports `WebKit`.
- The same protocol test suite runs against every engine that's available on the machine.

### Sidebar data model

Sela uses the same shape Arc uses, because it's proven and makes import a straight mapping.

- A flat list of items, each with `id`, `parentID`, `childrenIds`, `title`, `createdAt`, and a `data` payload that is one of:
  - `tab`: saved URL, saved title, last active time, mute status
  - `list`: a folder, with an optional custom icon
  - `itemContainer`: the root container for a space's pinned items, unpinned items, or the favourites grid
- Spaces reference their containers, a colour theme, an icon and a profile.
- An ordered list of space IDs and the favourites container ID sit at the top level.
- The whole sidebar is stored as one JSON file in Sela's Application Support folder, written atomically. Archived tabs go in a separate JSON file, like Arc's `StorableArchive`.

### Import from Arc

Arc stores its sidebar in `~/Library/Application Support/Arc/StorableSidebar.json`. Its top level has `sidebar.containers`, where the second container holds `items`, `spaces` and `topAppsContainerIDs`. Item and space shapes match the model above. The importer reads this file read-only and builds Sela's sidebar from it.

History comes from the `History` SQLite database in Arc's Chromium profile in `~/Library/Application Support/Arc/User Data/`, read directly. Arc must be closed during import because it locks that database while it runs. Passwords and cookies stay with Arc: the owner exports passwords from Arc into a password manager, and signs in to websites again once.

**Arc snapshot tool.** Nobody knows whether Arc keeps launching, or keeps its data, after the December shutdown. A small standalone tool copies Arc's Application Support folder to a safe location, and the importer reads from either the live Arc folder or a snapshot. It gets built first, and the owner runs it before December.

### Import from Chrome, Brave, Edge and Safari

Without Arc, the first launch offers the browser the owner most likely uses: the default browser, or else the one used most recently. Settings > Import can import from any of them at any time. The `BrowserImport` package finds each browser's profiles (`Default` and `Profile N` under Application Support for the Chromium browsers, `~/Library/Safari` for Safari) and reads them without writing:

- Bookmarks come from Chromium's `Bookmarks` JSON and Safari's `Bookmarks.plist`. The bookmarks bar becomes pinned tabs and folders at the end of the current space's pinned section, in order and with folders nested. Chromium's other and mobile bookmarks, and Safari's bookmarks menu, follow as folders. Favourites aren't touched. Non-web addresses, and addresses already pinned in the space or in favourites, are skipped, and folders with a matching name merge, so importing twice adds nothing.
- History from the last 90 days merges into Sela's history the same way Arc's does. Browsers lock their history database while they run, so the importer copies it and its write-ahead log to a temporary folder and reads the copy. Chromium counts microseconds from 1601, Safari seconds from 2001.
- Safari's folder needs Full Disk Access. A refused read is reported on its own, and Sela explains it with a button that opens that pane of System Settings.

### Sync

CloudKit private database, one record per sidebar item and space, with each user's data in their own iCloud account. Arc's earlier CloudKit sync stored per-item records plus an ordered space list and a container record, which is the model to follow. Conflicts resolve per item, last write wins, with deletions tracked so a deleted item can't come back from a stale device.

## Repository layout

```
sela/
  README.md              what Sela is, how to build it, what each folder holds
  LICENSE
  assets/                Sela's own icons and artwork
  docs/
    design/              design documents like this one
    building.md          building, signing and releasing
  app/
    Sela.xcodeproj       the macOS app target
    Sela/                app entry point, window management, menus
    Packages/            one Swift package per feature: Sidebar, Spaces,
                         CommandBar, SplitView, Peek, Archive, ArcImport,
                         Sync, Settings, BrowserEngine (engine protocols),
                         WebKitEngine, FakeEngine
  scripts/               build, sign, notarize, release
  .github/workflows/     CI for the Swift app
```

## Decisions

Made by the owner:

- Use as few resources as possible, decided 2026-10-24. Unused tabs sleep after 15 minutes and wake where they were, and memory warnings from macOS sleep every background tab.
- Content blocking, decided 2026-10-23. Sela blocks ads and trackers by default with EasyList and EasyPrivacy, converted by AdGuard's SafariConverterLib into WebKit content rules, with a switch per site.
- Sela is licensed GPL-3.0, decided 2026-10-23, because AdGuard's library is GPL-3.0.
- WebKit for good, decided 2026-10-23. This replaces the earlier plan of a Chromium fork. Sela stays small and builds on any Mac, needs no Widevine licence and has no engine to update every 4 weeks. It gives up Chrome extensions.
- Native Mac UI in Swift and AppKit. Not web-drawn.
- Mac only.
- First version: sidebar, command bar, split view, Peek, Arc import, CloudKit sync. Little Arc later. Boosts never.
- CloudKit for sync.
- The owner tests builds and judges the feel.

Made as calls during design. The owner can override any of these:

- Sync is built last in the first version.
- The JSON storage format mirrors Arc's.
- Sparkle for self-updates, as Arc uses. Release builds and the update feed are hosted on GitHub Releases, which keeps Sela free of a server.
- No crash reporting service by default.
- One profile for all spaces in the first version.
- Feature state uses Swift's Observation framework (`@Observable` stores per feature) instead of The Composable Architecture. It's simpler for a small team and doesn't fight AppKit.

## Suggested milestones

0. **Arc snapshot tool.** Built and run before December. Done.
1. **Sidebar data model, storage and the Arc sidebar importer.** Done.
2. **Engine protocols, `FakeEngine`, `WebKitEngine` and a window that browses.** Done.
3. **The sidebar UI.** Spaces, pinned tabs, folders, favourites, unpinned tabs, drag and drop, swiping and animations. Done.
4. **Archiving and the command bar.** Done.
5. **Split view and Peek.**
6. **Browser essentials.** Downloads, find in page, permissions, history import from Arc and settings.
7. **CloudKit sync.**
8. **Release.** Signing, notarization, Sparkle updates, a public DMG.

## Left to the builder

- The archive search UI, the command bar ranking, and keyboard shortcut defaults. These follow Arc's defaults unless there's a reason not to.
- Animation timings and spring curves, tuned by feel against Arc on the owner's Mac.
- CI details.
