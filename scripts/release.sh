#!/bin/sh
# Builds a Developer ID signed, notarized Sela for a GitHub release: a disk image for people to
# download, a zip for Sparkle to update from, and the update feed that points at the zip.
#
# Needs a "Developer ID Application" certificate in your keychain, the asc CLI logged in to
# App Store Connect with a key that can notarize, and Sela's update signing key in your login
# keychain (made once with Sparkle's generate_keys). Usage: scripts/release.sh TEAM_ID
#
# Everything lands in .build/release/Build/Products/Release. Upload these three to the release:
#   Sela.dmg            the website links to releases/latest/download/Sela.dmg
#   Sela-<version>.zip  what Sparkle downloads
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
rm -rf "$products/Sela-notarize.zip" "$zip" "$dmg" "$products/appcast" "$products/appcast.xml" "$products/dmg"

# Notarize the app and staple the ticket to it, so it opens offline too.
ditto -c -k --keepParent "$products/Sela.app" "$products/Sela-notarize.zip"
asc notarization submit --file "$products/Sela-notarize.zip" --wait --timeout 30m --output json
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
asc notarization submit --file "$dmg" --wait --timeout 30m --output json
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature "$dmg"

# The update feed, signed with the key in your keychain. It lists this release only.
mkdir "$products/appcast"
cp "$zip" "$products/appcast/"
"$sparkle/generate_appcast" \
    --download-url-prefix "https://github.com/DotDeon/sela/releases/download/v$version/" \
    --link "https://github.com/DotDeon/sela/releases" \
    -o "$products/appcast.xml" "$products/appcast"
rm -rf "$products/appcast"

shasum -a 256 "$dmg" "$zip"
