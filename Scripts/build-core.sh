#!/usr/bin/env bash
# Builds ClamshellBridge.xcframework (melonDS core + C facade) for iOS device, iOS
# Simulator and macOS (host tests). JIT is disabled; the script fails if any JIT code or
# executable-memory API makes it into an archive.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: Scripts/build-core.sh [Release|Debug]
# Requires: Xcode, cmake >= 3.24, ninja.

set -euo pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Core/Bridge"
BUILD="$ROOT/.build/core"
OUT="$ROOT/Packages/ClamshellCore/Artifacts/ClamshellBridge.xcframework"
IOS_TARGET=27.0
MACOS_TARGET=15.0

if [[ ! -f "$ROOT/Vendor/melonDS/CMakeLists.txt" ]]; then
    echo "error: Vendor/melonDS is missing. Run: git submodule update --init" >&2
    exit 1
fi

# name | extra cmake arguments
SLICES=(
    "ios|-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_TARGET"
    "ios-simulator|-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_TARGET"
    "macos|-DCMAKE_OSX_SYSROOT=macosx -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_TARGET"
)

check_no_jit() {
    local lib="$1"
    # Defined JIT code, or any API that creates executable memory.
    if nm -gU "$lib" 2>/dev/null | grep -qE 'ARMJIT|JitBlock'; then
        echo "error: $lib contains JIT symbols" >&2; exit 1
    fi
    if nm -u "$lib" 2>/dev/null | grep -qE '_(mprotect|vm_protect|mach_vm_protect|pthread_jit_write_protect_np|sys_icache_invalidate)$'; then
        echo "error: $lib references an executable-memory API" >&2; exit 1
    fi
}

XCF_ARGS=()
for slice in "${SLICES[@]}"; do
    name="${slice%%|*}"
    extra="${slice#*|}"
    dir="$BUILD/$name"
    echo "==> $name ($CONFIG)"

    # shellcheck disable=SC2086
    cmake -S "$SRC" -B "$dir" -G Ninja -Wno-dev \
        -DCMAKE_BUILD_TYPE="$CONFIG" -DCMAKE_OSX_ARCHITECTURES=arm64 $extra >/dev/null
    cmake --build "$dir" --target ClamshellBridge

    merged="$dir/libClamshellBridgeAll.a"
    libtool -static -no_warning_for_no_symbols -o "$merged" \
        "$dir/libClamshellBridge.a" \
        "$dir/melonDS/src/libcore.a" \
        "$dir/melonDS/src/teakra/src/libteakra.a"
    check_no_jit "$merged"

    headers="$dir/headers"
    rm -rf "$headers" && mkdir -p "$headers"
    cp "$SRC/include/ClamshellBridge.h" "$SRC/include/module.modulemap" "$headers/"

    XCF_ARGS+=(-library "$merged" -headers "$headers")
done

rm -rf "$OUT"
xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "$OUT" >/dev/null
echo "==> $OUT"
