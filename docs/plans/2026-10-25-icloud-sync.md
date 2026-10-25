# iCloud sync

**Goal:** spaces, pinned tabs, folders, favourites and profiles follow you to your other Macs through your own iCloud account. Today's tabs, the archive and history stay on each Mac. There is no Sela server.

**Where it stands:** everything is built and sits behind the iCloud entitlements, which only work in a copy of Sela signed with a Developer ID provisioning profile that allows them. Team KNU6L342KX hasn't set that up yet. The build Sela ships today isn't signed with them, so Settings has no Sync tab and nothing talks to CloudKit. Turning it on is a signing change, described in "Switching it on" below, plus deploying the CloudKit schema. No code changes.

**Sources:** the macOS 27 SDK in Xcode 27, the CloudKit Swift interface for `CKSyncEngine`, and Apple's CloudKit and Developer ID documentation.

## How it works

### Records, not a blob

The sidebar on disk, `Sidebar.json`, stays the source of truth. Sync is a layer over it in the `CloudSync` module:

- Each space, each profile, and each item in a pinned section or in favourites is one CloudKit record in a zone called `SelaSidebar` in the private database of the container `iCloud.app.brow.Brow`. Record types are `SelaSpace`, `SelaItem` and `SelaProfile`. Record names are the sidebar's own IDs with a prefix, `item:<id>`, so a tab keeps its identity across Macs.
- A record's fields are a change tag (`tagDate`, `tagDevice`, `tagDeviceName`), a `deleted` flag and `body`, the item as JSON in an encrypted field. One body field means the sidebar's shape can change without touching the CloudKit schema.
- Unpinned sections and the tabs in them never become records. Neither do the parts of an item that belong to one Mac: when a tab was last active, whether it's unread, whether a folder is open.
- Every Mac gave its favourites container its own ID, so that one record travels under the name `favorites` and each Mac puts its own ID back.
- A space's record carries its pinned section's ID and its profile. Each Mac keeps its own unpinned section for the space, and makes one when a space arrives from another Mac.

### Merging

- Last writer wins per record. The change tag is the time of the edit plus a per-Mac ID that breaks ties, so every Mac picks the same winner.
- Deletions are tombstones: the record stays with `deleted` set and a new tag. A Mac that was off for a week learns of the deletion, and an edit made after it on another Mac still wins and brings the item back.
- After the records are folded in, the tree is repaired. Two Macs can leave an item claimed by two folders, a folder inside itself, a split with one pane, or an item whose folder is gone. The item's own record says where it lives; failing that, the parent written last keeps it. Anything left without a home goes in a folder named "Recovered from <Mac>" in the first space's pinned section, named for the Mac the item came from. Nothing is dropped.
- Guard against an empty or broken iCloud state: a merge that would remove more than half the synced items waits. Sela asks whether to keep this Mac's sidebar or remove the items. Keeping them gives them a fresh tag and sends them back up, so they return on the other Macs too.
- A sidebar from iCloud that still doesn't hold together after repair isn't applied. This Mac keeps its own and Settings says so.
- The first time sync is turned on, this Mac's records get a tag from the distant past. A sidebar already in iCloud wins where the two overlap, and what this Mac alone has still goes up. If iCloud is empty, everything goes up.

### Transport

- `CKSyncEngine` does the sending, fetching, batching, retrying, push subscriptions and account changes. `CloudKitTransport` is its delegate and translates its events for the model. The engine's own state is kept in `CloudSync.json` beside `Sidebar.json`, along with the tag, body and CloudKit system fields of every record this Mac knows. Losing that file only means a full compare on the next sync.
- A save that CloudKit refuses because the server has a newer version goes through the same merge as a fetched record. If this Mac's version is still newer, it's sent again on top of the server's.
- Signing out of iCloud pauses sync and forgets the server copies. Signing in again starts over with that account. A zone deleted from iCloud, for example in System Settings > iCloud > Manage Storage, is made again and everything goes up.
- `CloudSyncModel` watches `SidebarStore.document` and, a second after a change, compares the sidebar with the ledger and queues what differs. It applies merges through `SidebarStore.edit`, so the store's own save handles the file.

### What the person sees

- Settings > Sync, only in a copy with the entitlements: a switch, off by default; the iCloud account status; when it last synced; this Mac's name; a Sync Now button; and text saying what syncs and what stays local.
- A banner in the frontmost window when sync pauses because iCloud is signed out, full or restricted.
- An alert when a merge would remove most of the sidebar, with "Keep This Mac's Sidebar" as the default and "Remove Them" as the destructive choice.

## Switching it on

1. **Make the App ID and container.** In Certificates, Identifiers & Profiles, open the identifier `app.brow.Brow`, or make it as an explicit App ID for macOS. Tick iCloud, choose CloudKit, and under its Configure button make the container `iCloud.app.brow.Brow` and assign it. Tick Push Notifications too; CloudKit's silent pushes need it.
2. **Make a Developer ID provisioning profile.** Under Profiles, add a profile, choose Developer ID under Distribution, pick `app.brow.Brow` and the Developer ID Application certificate, and download it. Keep the file out of git. Check it with `security cms -D -i Sela.provisionprofile` and look under `Entitlements` for `com.apple.developer.icloud-container-identifiers` listing the container, `com.apple.developer.icloud-services` and `com.apple.developer.aps-environment` set to `production`. Whenever the certificate is renewed, make a new profile. One profile can also carry the passkey entitlement from `docs/plans/2026-10-24-passkeys.md` once Apple grants it.
3. **Set up the schema.** Open the CloudKit Console at icloud.developer.apple.com, pick the container, and in the Development environment make the record types `SelaSpace`, `SelaItem` and `SelaProfile`, each with fields `tagDate` (Date/Time), `tagDevice` (String), `tagDeviceName` (String), `deleted` (Int64) and `body` (Bytes, encrypted). The sync engine fetches changes by zone, which needs no indexes. Running a Debug build signed for iCloud against the Development environment also makes the types on first save. Then Deploy Schema Changes to Production. A Developer ID build uses Production, and records it saves there go nowhere until the schema is deployed.
4. **Build a release with it on your Mac.** Run `SELA_CLOUD=1 SELA_PROFILE=~/path/to/Sela.provisionprofile scripts/release.sh KNU6L342KX`. With `SELA_CLOUD=1`, release.sh checks that the profile is a Developer ID profile for `KNU6L342KX.app.brow.Brow` that allows the container and production pushes, and stops if not. It builds the entitlements from `app/Support/Sela.entitlements` plus the iCloud keys, puts the profile in the app as `Contents/embedded.provisionprofile`, and signs with them. Add `SELA_PASSKEYS=1` to sign with both; the profile then has to allow both. Without the variables, release.sh does exactly what it did before.
5. **Check the build before publishing it.**
   - `codesign -d --entitlements - .build/release/Build/Products/Release/Sela.app` lists `com.apple.developer.icloud-container-identifiers` with the container.
   - Sela opens. If macOS refuses to open it, the profile and entitlements don't match.
   - Settings shows a Sync tab, and turning it on shows "Signed in" and, after a moment, a last synced time.
   - On a second Mac signed in to the same iCloud account, turn sync on. Within a minute the first Mac's spaces, pinned tabs, folders, favourites and profiles appear, and today's tabs don't. Pin a tab on each Mac and check it shows on the other.
   - Delete a pinned tab on one Mac and check it goes on the other. Then, with sync off on one Mac, remove most of its pinned tabs on the other, turn sync back on, and check the alert appears and "Keep This Mac's Sidebar" brings them back everywhere.
   - In the CloudKit Console, check records in Production carry a `body` and nothing readable beyond the tag fields.
6. **Do the same in the Release workflow.** Add the profile as a repository secret `SELA_PROFILE_BASE64`, made with `base64 -i Sela.provisionprofile`. In `.github/workflows/release.yml`, decode it in the "Put the signing certificate and keys in place" step to `$RUNNER_TEMP/Sela.provisionprofile`, delete it in "Remove the keys", and add `SELA_CLOUD: "1"` and `SELA_PROFILE: ${{ runner.temp }}/Sela.provisionprofile` to the build step's `env`.
7. **Keep the entitlements files in step.** Anything added to `Sela.entitlements` later goes in `Sela-Cloud.entitlements` and `Sela-Passkeys.entitlements` too. release.sh builds its own file from `Sela.entitlements`, so the two static files are for Xcode.

To try it in Debug before a release, sign with an Apple Development certificate and a macOS development profile for `app.brow.Brow` that includes iCloud and Push Notifications, and set `CODE_SIGN_ENTITLEMENTS = Support/Sela-Cloud.entitlements` in `app/Support/Signing.local.xcconfig`. Xcode fills in the team and bundle ID itself, and a development build talks to the Development environment, so it needs the schema there. The project default stays ad hoc with `Sela.entitlements`. Note that `aps-environment` is `production` in `Sela-Cloud.entitlements`; a development profile wants `development`, so change that line locally while testing in Debug and don't commit it.

## Limits

- Sync needs macOS to see the entitlements on Sela's signature. A copy built ad hoc on someone's own Mac has no Sync tab.
- Tombstones stay in iCloud and in `CloudSync.json` for good. They're small, a few hundred bytes each, but a sidebar used hard for years will carry thousands. A later change could delete tombstones older than 90 days with `recordIDsToDelete`.
- Turning sync off doesn't remove anything from iCloud. Removing Sela's data is done in System Settings > iCloud > Manage Storage, or could be a button later.
- Profiles sync as names and colours. Their cookies and logins don't, and can't, since each Mac's WebKit data store is its own.
- A space's theme and icon sync; the window and sidebar width don't.
- Reordering spaces is a record change per space, since each carries its position. Two Macs reordering at once end with the later Mac's order for the spaces it touched.
