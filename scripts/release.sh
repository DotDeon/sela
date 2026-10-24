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
sign --entitlements app/Support/Sela.entitlements "$products/Sela.app"
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
