#!/bin/sh
# Starts a release. It sets Sela's version, adds one to the build number, commits, tags and pushes,
# and the Release workflow on GitHub does the rest. Usage: scripts/ship.sh 0.1.4
set -eu
cd "$(dirname "$0")/.."
version="${1:?usage: scripts/ship.sh VERSION}"
project=app/Sela.xcodeproj/project.pbxproj

git diff --quiet && git diff --cached --quiet || { echo "Commit or stash your changes first."; exit 1; }
test "$(git branch --show-current)" = main || { echo "Releases go out from main."; exit 1; }

build=$(grep -m1 'CURRENT_PROJECT_VERSION' "$project" | sed 's/.*= \(.*\);/\1/')
sed -i '' "s/CURRENT_PROJECT_VERSION = $build;/CURRENT_PROJECT_VERSION = $((build + 1));/; s/MARKETING_VERSION = .*;/MARKETING_VERSION = $version;/" "$project"

git commit -qam "Version $version"
git tag "v$version"
git push origin main "v$version"
echo "Release v$version started: https://github.com/DotDeon/sela/actions/workflows/release.yml"
