#!/bin/sh
# Builds a Developer ID signed, notarized Sela for a GitHub release: a disk image for people to
# download, a zip for Sparkle to update from, and the update feed that points at the zip.
#
# Needs a "Developer ID Application" certificate in your keychain, the gh CLI logged in to
# GitHub, and Sela's update signing key. On your Mac it notarizes with the asc CLI and reads the
# signing key from your login keychain. On GitHub Actions it notarizes with notarytool and reads
# the key from a file, when these are set:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER  an App Store Connect API key
#   SPARKLE_KEY_FILE                               the update signing key, from generate_keys -x
# These add entitlements that need a Developer ID provisioning profile, which goes inside the app.
# Either or both can be on; the profile has to allow everything that is.
#   SELA_PASSKEYS=1  the browser passkey entitlement, so websites can use passkeys. Apple has to grant
#                    it to the team first. See docs/plans/2026-10-24-passkeys.md.
#   SELA_CLOUD=1     iCloud, so the sidebar syncs between Macs through CloudKit and silent pushes.
#                    See docs/plans/2026-10-25-icloud-sync.md.
#   SELA_PROFILE     the Developer ID provisioning profile that allows them
# Usage: scripts/release.sh TEAM_ID
#
# Everything lands in .build/release/Build/Products/Release. Upload these to the release:
#   Sela.dmg            the website links to releases/latest/download/Sela.dmg
#   Sela-<version>.zip  what Sparkle downloads
#   *.delta             only what changed since recent versions, so most updates are small
#   appcast.xml         installed apps check releases/latest/download/appcast.xml
set -eu
cd "$(dirname "$0")/.."
team="${1:?usage: scripts/release.sh TEAM_ID}"
products=.build/release/Build/Products/Release
sparkle=.build/release/SourcePackages/artifacts/sparkle/Sparkle/bin
entitlements=app/Support/Sela.entitlements
passkeys="${SELA_PASSKEYS:-}"
cloud="${SELA_CLOUD:-}"
if [ "$passkeys" = 1 ] || [ "$cloud" = 1 ]; then
    profile="${SELA_PROFILE:?SELA_PASSKEYS=1 and SELA_CLOUD=1 need SELA_PROFILE, the path to the Developer ID provisioning profile}"
    [ -f "$profile" ] || { echo "No provisioning profile at $profile"; exit 1; }
fi

xcodebuild -project app/Sela.xcodeproj -scheme Sela -configuration Release \
    -derivedDataPath .build/release -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
    PROVISIONING_PROFILE_SPECIFIER="" CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" build

# Xcode signs Sparkle's framework but not the helpers inside it, and notarization refuses those.
# Sign them inside out with Developer ID, a secure timestamp and the hardened runtime, then sign
# Sela again so its signature covers them.
sign() { codesign --force --sign "Developer ID Application" --options runtime --timestamp "$@"; }
framework="$products/Sela.app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$framework/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$framework/XPCServices/Downloader.xpc"
sign "$framework/Autoupdate"
sign "$framework/Updater.app"
sign "$products/Sela.app/Contents/Frameworks/Sparkle.framework"

# A restricted entitlement needs a profile that allows it inside the app, or macOS refuses to open Sela.
# So check the profile matches this team and app and carries each entitlement before using it, then
# put together the entitlements file: the usual one, plus what each switch adds.
if [ "$passkeys" = 1 ] || [ "$cloud" = 1 ]; then
    bundle=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$products/Sela.app/Contents/Info.plist")
    decoded=.build/release/profile.plist
    security cms -D -i "$profile" > "$decoded"
    field() { /usr/libexec/PlistBuddy -c "Print $1" "$decoded" 2>/dev/null || true; }
    [ "$(field :Entitlements:com.apple.application-identifier)" = "$team.$bundle" ] \
        || { echo "The profile isn't for $team.$bundle"; exit 1; }
    [ "$(field :ProvisionsAllDevices)" = true ] \
        || { echo "The profile isn't a Developer ID profile"; exit 1; }
    entitlements=.build/release/Sela-Signed.entitlements
    cp app/Support/Sela.entitlements "$entitlements"
    add() { /usr/libexec/PlistBuddy -c "Add $1 $2 $3" "$entitlements"; }
    add :com.apple.application-identifier string "$team.$bundle"
    add :com.apple.developer.team-identifier string "$team"
    if [ "$passkeys" = 1 ]; then
        [ "$(field :Entitlements:com.apple.developer.web-browser.public-key-credential)" = true ] \
            || { echo "The profile doesn't allow com.apple.developer.web-browser.public-key-credential"; exit 1; }
        add :com.apple.developer.web-browser.public-key-credential bool true
    fi
    if [ "$cloud" = 1 ]; then
        container=iCloud.app.brow.Brow
        field :Entitlements:com.apple.developer.icloud-container-identifiers | grep -q "$container" \
            || { echo "The profile doesn't allow the iCloud container $container"; exit 1; }
        [ "$(field :Entitlements:com.apple.developer.aps-environment)" = production ] \
            || { echo "The profile doesn't allow push notifications (aps-environment production)"; exit 1; }
        add :com.apple.developer.icloud-services array
        add :com.apple.developer.icloud-services:0 string CloudKit
        add :com.apple.developer.icloud-container-identifiers array
        add :com.apple.developer.icloud-container-identifiers:0 string "$container"
        add :com.apple.developer.aps-environment string production
    fi
    rm "$decoded"
    cp "$profile" "$products/Sela.app/Contents/embedded.provisionprofile"
fi
sign --entitlements "$entitlements" "$products/Sela.app"
codesign --verify --deep --strict "$products/Sela.app"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$products/Sela.app/Contents/Info.plist")
zip="$products/Sela-$version.zip"
dmg="$products/Sela.dmg"
rm -rf "$products/Sela-notarize.zip" "$zip" "$dmg" "$products/appcast" "$products/appcast.xml" "$products/dmg" "$products"/*.delta

notarize() {
    if [ -n "${NOTARY_KEY_PATH:-}" ]; then
        xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --timeout 30m
    else
        asc notarization submit --file "$1" --wait --timeout 30m --output json
    fi
}

# Notarize the app and staple the ticket to it, so it opens offline too.
ditto -c -k --keepParent "$products/Sela.app" "$products/Sela-notarize.zip"
notarize "$products/Sela-notarize.zip"
rm "$products/Sela-notarize.zip"
xcrun stapler staple "$products/Sela.app"
spctl -a -t exec "$products/Sela.app"

# The zip Sparkle installs from.
ditto -c -k --keepParent "$products/Sela.app" "$zip"

# The disk image: Sela beside a link to Applications, signed and notarized in its own right.
mkdir "$products/dmg"
ditto "$products/Sela.app" "$products/dmg/Sela.app"
ln -s /Applications "$products/dmg/Applications"
hdiutil create -volname Sela -srcfolder "$products/dmg" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$products/dmg"
codesign --sign "Developer ID Application" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature "$dmg"

# The update feed. It lists this release only, but the current release's zip sits beside it so
# Sparkle can make a delta from the last version to this one.
mkdir "$products/appcast"
gh release download --repo DotDeon/sela --pattern 'Sela-*.zip' --dir "$products/appcast" || true
cp "$zip" "$products/appcast/"
key=""
[ -n "${SPARKLE_KEY_FILE:-}" ] && key="--ed-key-file $SPARKLE_KEY_FILE"
# shellcheck disable=SC2086
"$sparkle/generate_appcast" $key --maximum-versions 1 \
    --download-url-prefix "https://github.com/DotDeon/sela/releases/download/v$version/" \
    --link "https://github.com/DotDeon/sela/releases" \
    -o "$products/appcast.xml" "$products/appcast"
mv "$products/appcast"/*.delta "$products/" 2>/dev/null || true
rm -rf "$products/appcast"

shasum -a 256 "$dmg" "$zip"
