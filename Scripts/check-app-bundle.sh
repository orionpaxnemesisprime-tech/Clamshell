#!/usr/bin/env bash
# Fails if a built Clamshell.app breaks the app-store-compliance rules that can be checked
# mechanically: no game, BIOS or firmware files in the bundle, no JIT entitlement, and no
# JIT or executable-memory symbols in the binary.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: Scripts/check-app-bundle.sh path/to/Clamshell.app

set -euo pipefail
app="${1:?usage: $0 path/to/Clamshell.app}"
status=0

files=$(find "$app" -type f \( -iname '*.nds' -o -iname '*.srl' -o -iname '*.dsi' -o -iname '*.ids' \
    -o -iname 'bios*.bin' -o -iname 'firmware*.bin' -o -iname '*.gba' \) )
if [ -n "$files" ]; then
    echo "error: game, BIOS or firmware files in the bundle:" >&2
    echo "$files" >&2
    status=1
fi

if codesign -d --entitlements - "$app" 2>/dev/null | grep -q 'com.apple.security.cs.'; then
    echo "error: the app requests a code-signing (cs.*) entitlement such as allow-jit" >&2
    status=1
fi

# Every Mach-O in the bundle (Debug builds keep the code in Clamshell.debug.dylib).
while IFS= read -r file; do
    if file -b "$file" | grep -q 'Mach-O' &&
       nm "$file" 2>/dev/null | grep -qE 'ARMJIT|JitBlock|_pthread_jit_write_protect_np|_mprotect$|_vm_protect$'; then
        echo "error: $file contains JIT or executable-memory symbols" >&2
        status=1
    fi
done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \))

[ "$status" -eq 0 ] && echo "App bundle checks passed."
exit "$status"
