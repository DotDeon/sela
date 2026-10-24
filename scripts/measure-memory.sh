#!/bin/sh
# Measures how much memory Brow uses with the pages in scripts/measure-pages.txt loaded,
# then again after unused tabs have gone to sleep.
#
# Runs a Release build with a throwaway data folder, so your own sidebar isn't touched.
# Quit Brow, Safari and Mail first: their WebKit processes would be counted too.
set -eu
cd "$(dirname "$0")/.."

if pgrep -x Brow >/dev/null; then
    echo "Quit Brow first." >&2
    exit 1
fi

pages="$PWD/scripts/measure-pages.txt"
count=$(grep -c . "$pages")
data=$(mktemp -d "${TMPDIR:-/tmp}/brow-measure.XXXXXX")
app=.build/measure/Build/Products/Release/Brow.app

xcodebuild -project app/Brow.xcodeproj -scheme Brow -configuration Release \
    -derivedDataPath .build/measure -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build >/dev/null

# Footprint in MB of one process.
footprint_mb() {
    footprint -p "$1" 2>/dev/null | awk '/Footprint:/ {
        for (i = 1; i < NF; i++) if ($i == "Footprint:") { v = $(i+1); u = $(i+2) }
        if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024
        printf "%.0f", v; exit }'
}

# Brow plus every WebKit process that wasn't running before it started.
total_mb() {
    sum=$(footprint_mb "$brow")
    for pid in $(pgrep -f "com.apple.WebKit"); do
        case " $before " in *" $pid "*) continue ;; esac
        sum=$((sum + $(footprint_mb "$pid")))
    done
    echo "$sum"
}

before=$(pgrep -f "com.apple.WebKit" | tr '\n' ' ')
"$app/Contents/MacOS/Brow" -BrowDataFolder "$data" -BrowOpenPages "$pages" -SleepTabsAfterSeconds 60 >/dev/null 2>&1 &
brow=$!

sleep $((count * 4 + 20))
echo "Loaded, $count pages:   $(total_mb) MB"
sleep 90
echo "After tabs slept:     $(total_mb) MB"

kill "$brow"
wait "$brow" 2>/dev/null || true
rm -rf "$data"
