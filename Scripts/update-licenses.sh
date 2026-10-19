#!/usr/bin/env bash
# Regenerates the licence texts bundled in the app (Clamshell/Licenses) from the repo's
# LICENSE, THIRD_PARTY_LICENSES and the vendored sources. Binary distribution requires the
# full licence texts, so run this whenever a dependency is added, removed or bumped.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: Scripts/update-licenses.sh [--check]   (--check: fail if the bundled copies are stale)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/melonDS/src"
DEST="$ROOT/Clamshell/Licenses"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

section() {
    printf '\n\n================================================================================\n'
    printf '%s\n' "$1"
    printf '================================================================================\n\n'
}

# First /* ... */ comment block of a file, without the comment markers.
leading_comment() {
    awk 'NR == 1 && !/\/\*/ { exit } { print } /\*\// { exit }' "$1" | sed -e 's#^/\*##' -e 's#\*/$##'
}

cp "$ROOT/LICENSE" "$OUT/GPL-3.0.txt"
cp "$ROOT/THIRD_PARTY_LICENSES" "$OUT/ThirdPartyComponents.txt"

{
    printf 'Licence texts of the third-party components compiled into Clamshell.\n'
    printf 'melonDS itself is licensed under the GNU GPL v3 (see the GPL-3.0 text).\n'

    section "FreeBIOS (BSD-2-Clause)"
    leading_comment "$SRC/FreeBIOS.cpp"

    section "Teakra (MIT)"
    cat "$SRC/teakra/LICENSE"

    section "FatFs (FatFs licence, BSD-style)"
    cat "$SRC/fatfs/LICENSE.txt"

    section "xxHash (BSD-2-Clause)"
    leading_comment "$SRC/xxhash/xxhash.h"

    section "tiny-AES-c (Unlicense)"
    cat "$SRC/tiny-AES-c/unlicense.txt"

    section "SHA-1 in C (public domain)"
    printf 'SHA-1 in C\nBy Steve Reid <steve@edmweb.com>\n100%% Public Domain\n'

    section "blip_buf (GNU LGPL v2.1 or later)"
    printf 'Library Copyright (C) 2003-2009 Shay Green.\n\n'
    cat "$SRC/blip-buf/license.txt"
} > "$OUT/ThirdPartyNotices.txt"

if [[ "${1:-}" == "--check" ]]; then
    if ! diff -rq "$OUT" "$DEST" >/dev/null 2>&1; then
        echo "error: Clamshell/Licenses is out of date. Run Scripts/update-licenses.sh" >&2
        exit 1
    fi
    echo "Licences up to date."
else
    mkdir -p "$DEST"
    cp "$OUT"/*.txt "$DEST/"
    echo "Wrote $(ls "$OUT" | wc -l | tr -d ' ') files to $DEST"
fi
