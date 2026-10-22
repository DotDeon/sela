<img src="assets/icon.svg" width="64" height="64" alt="">

# Brow

Brow is an open-source Mac browser built to work like Arc: favourites at the top of a sidebar, pinned tabs and folders, unpinned tabs that archive themselves, and spaces you swipe between. It runs on Chromium so Chrome extensions work, with a native Swift interface on top. The design lives in [`docs/design/2026-10-23-brow-design.md`](docs/design/2026-10-23-brow-design.md).

Brow is early. Today the repository holds the sidebar data model, an importer for Arc's sidebar, and a tool that backs up your Arc data.

## Folder layout

```
assets/        Brow's own icons and artwork
docs/design/   design documents
docs/plans/    implementation plans
app/Packages/  Swift package with one module per feature
chromium/      Chromium patches and Brow's C++ code (coming later)
scripts/       build, sign and release scripts (coming later)
```

Inside `app/Packages`:

- `SidebarModel`: spaces, tabs, folders and favourites, and how they're saved to disk
- `ArcImport`: reads Arc's `StorableSidebar.json` into Brow's sidebar
- `ArcSnapshot`: copies Arc's data folder, minus caches, so it survives Arc shutting down
- `brow-arc`: command-line tool for the two above

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

To see what Brow would import from your live Arc data or from a snapshot:

```bash
swift run --package-path app/Packages brow-arc inspect
swift run --package-path app/Packages brow-arc inspect --root "/Volumes/Backup/Arc-snapshot-<date>"
```

Neither command changes anything in Arc's folder.
