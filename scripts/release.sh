#!/bin/sh
# Builds a Developer ID signed, notarized Brow.app and zips it for a GitHub release.
#
# Needs a "Developer ID Application" certificate in your keychain, and the asc CLI logged in to
# App Store Connect with a key that can notarize. Usage: scripts/release.sh TEAM_ID
# The zip lands in .build/release/Build/Products/Release/Brow-<version>.zip.
set -eu
cd "$(dirname "$0")/.."
team="${1:?usage: scripts/release.sh TEAM_ID}"
products=.build/release/Build/Products/Release

xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Release \
    -derivedDataPath .build/release -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
    PROVISIONING_PROFILE_SPECIFIER="" CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" build

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$products/Brow.app/Contents/Info.plist")
rm -f "$products/Brow-notarize.zip" "$products/Brow-$version.zip"
ditto -c -k --keepParent "$products/Brow.app" "$products/Brow-notarize.zip"
asc notarization submit --file "$products/Brow-notarize.zip" --wait --timeout 30m --output json
xcrun stapler staple "$products/Brow.app"
spctl -a -t exec "$products/Brow.app"
rm "$products/Brow-notarize.zip"
ditto -c -k --keepParent "$products/Brow.app" "$products/Brow-$version.zip"
shasum -a 256 "$products/Brow-$version.zip"
