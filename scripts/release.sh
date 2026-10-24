#!/bin/sh
# Builds a Developer ID signed, notarized Sela.app and zips it for a GitHub release.
#
# Needs a "Developer ID Application" certificate in your keychain, and the asc CLI logged in to
# App Store Connect with a key that can notarize. Usage: scripts/release.sh TEAM_ID
# The zips land in .build/release/Build/Products/Release: Sela-<version>.zip, and the same file as Sela.zip.
# Upload both. The website links to releases/latest/download/Sela.zip, so every release needs it.
set -eu
cd "$(dirname "$0")/.."
team="${1:?usage: scripts/release.sh TEAM_ID}"
products=.build/release/Build/Products/Release

xcodebuild -project app/Sela.xcodeproj -scheme Sela -configuration Release \
    -derivedDataPath .build/release -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
    PROVISIONING_PROFILE_SPECIFIER="" CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" build

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$products/Sela.app/Contents/Info.plist")
rm -f "$products/Sela-notarize.zip" "$products/Sela-$version.zip" "$products/Sela.zip"
ditto -c -k --keepParent "$products/Sela.app" "$products/Sela-notarize.zip"
asc notarization submit --file "$products/Sela-notarize.zip" --wait --timeout 30m --output json
xcrun stapler staple "$products/Sela.app"
spctl -a -t exec "$products/Sela.app"
rm "$products/Sela-notarize.zip"
ditto -c -k --keepParent "$products/Sela.app" "$products/Sela-$version.zip"
cp "$products/Sela-$version.zip" "$products/Sela.zip"
shasum -a 256 "$products/Sela-$version.zip"
