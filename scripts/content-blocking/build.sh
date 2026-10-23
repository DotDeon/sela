#!/bin/sh
# Builds app/Packages/Sources/WebKitEngine/Resources/content-blocking.js from AdGuard's content script.
# Run it after changing the versions in package.json, and commit the result.
set -eu
cd "$(dirname "$0")"
npm ci --silent
npx esbuild entry.js \
    --bundle --format=iife --minify \
    --alias:webextension-polyfill=./browser-stub.js \
    --banner:js="/* Built by scripts/content-blocking/build.sh from @adguard/safari-extension, @adguard/extended-css and @adguard/scriptlets (GPL-3.0, https://github.com/AdguardTeam). */" \
    --outfile=../../app/Packages/Sources/WebKitEngine/Resources/content-blocking.js
