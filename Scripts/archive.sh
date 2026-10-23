#!/usr/bin/env bash
# Archives a release build of Clamshell for App Store Connect, checks it, and tags the commit
# it was built from (GPLv3: every shipped build is tagged, and About links to that tag).
# It never uploads and never pushes: after checking the archive, push the tag and upload
# (Xcode Organizer or `asc`) yourself.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: REVENUECAT_API_KEY=appl_… Scripts/archive.sh
# The key is RevenueCat's public App Store SDK key; it is never committed. Test Store
# (test_…) keys are for development only and are refused here.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/archive"
cd "$ROOT"

key="${REVENUECAT_API_KEY:-}"
if [[ "$key" != appl_* ]]; then
    echo "error: set REVENUECAT_API_KEY to the App Store public SDK key (appl_…)" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain --ignore-submodules=none)" ]]; then
    echo "error: the working tree has uncommitted changes; ship only committed, public source" >&2
    exit 1
fi

Scripts/update-licenses.sh --check

settings=$(xcodebuild -project Clamshell.xcodeproj -scheme Clamshell -configuration Release \
    -showBuildSettings 2>/dev/null)
version=$(awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }' <<<"$settings")
build=$(awk -F' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }' <<<"$settings")
tag="v$version-$build"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "error: tag $tag already exists; bump CURRENT_PROJECT_VERSION for a new build" >&2
    exit 1
fi

archive="$OUT/Clamshell-$tag.xcarchive"
rm -rf "$archive"
xcodebuild -project Clamshell.xcodeproj -scheme Clamshell -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    REVENUECAT_API_KEY="$key" archive -quiet

app="$archive/Products/Applications/Clamshell.app"
Scripts/check-app-bundle.sh "$app"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :RevenueCatAPIKey' "$app/Info.plist")" != appl_* ]]; then
    echo "error: the archived app has no App Store RevenueCat key" >&2
    exit 1
fi

git tag -a "$tag" -m "Clamshell $version ($build)"
echo "Archived $archive and tagged $tag."
echo "Next: git push origin $tag, then upload the archive."
