#!/usr/bin/env python3
# Builds the app's Find Homebrew catalog from Scripts/homebrew/sources.json.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: python3 -I Scripts/build-homebrew-catalog.py <work-dir> [--default-icon ref.png]...
#
# Pass every known SDK placeholder icon (BlocksDS, devkitPro...) as --default-icon; keep them
# outside the repo, since they may depict console hardware.
#
# For every source entry it downloads the game into <work-dir> (never into the repo),
# verifies it with `swift run clamshell-catalog` (boots, keeps running, draws real content),
# and writes Clamshell/Homebrew/homebrew-catalog.json. Entries that fail are left out and
# reported. A game's own banner icon is bundled only when its licence clearly allows
# redistribution AND the icon isn't an SDK placeholder (which may depict console hardware).
#
# Entries without a direct download URL (e.g. itch.io pages) must be downloaded by hand into
# <work-dir>/<id>.nds first; they are then verified the same way.
#
# Clamshell only links to each game's page; this script never adds game files to the app.

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Scripts", "homebrew", "sources.json")
APP_DIR = os.path.join(ROOT, "Clamshell", "Homebrew")
PACKAGE = os.path.join(ROOT, "Packages", "ClamshellCore")

# Licences that clearly allow redistributing the game's art (so its icon can be bundled).
ICON_LICENCES = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib", "Unlicense", "CC0-1.0",
    "CC-BY-4.0", "CC-BY-SA-4.0", "GPL-2.0", "GPL-2.0-or-later", "GPL-3.0", "GPL-3.0-or-later",
    "LGPL-2.1", "LGPL-3.0", "MPL-2.0", "WTFPL",
}


def fetch(entry, work):
    """Returns the path of the entry's .nds in `work`, downloading it if possible."""
    target = os.path.join(work, entry["id"] + ".nds")
    if os.path.exists(target):
        return target
    url = entry.get("download", "")
    if not url.startswith("https://"):
        return None
    raw = os.path.join(work, entry["id"] + ".download")
    request = urllib.request.Request(url, headers={"User-Agent": "clamshell-catalog-builder"})
    with urllib.request.urlopen(request, timeout=120) as response, open(raw, "wb") as out:
        shutil.copyfileobj(response, out)
    if zipfile.is_zipfile(raw):
        with zipfile.ZipFile(raw) as archive:
            names = pick_game([n for n in archive.namelist() if not n.startswith("__MACOSX")])
            if not names:
                return None
            # Never extract paths from the archive; copy the member's bytes to a fixed name.
            with archive.open(names[0]) as member, open(target, "wb") as out:
                shutil.copyfileobj(member, out)
        os.remove(raw)
    elif is_archive(raw):
        # .7z / .rar / .tar.gz via macOS bsdtar: list, then stream one member to a fixed name.
        listing = subprocess.run(["bsdtar", "-tf", raw], capture_output=True, text=True).stdout.splitlines()
        names = pick_game(listing)
        if not names:
            return None
        with open(target, "wb") as out:
            subprocess.run(["bsdtar", "-xOf", raw, names[0]], stdout=out, check=True)
        os.remove(raw)
    else:
        os.replace(raw, target)
    return target


def download_note(url):
    """Tells players what they'll get when the download isn't a plain .nds on a release page."""
    path = url.lower().removesuffix("/download")
    if path.endswith(".zip"):
        return "The download is a ZIP file. Tap it in the Files app to unzip it, then open the game file."
    if path.endswith((".7z", ".rar", ".tar.gz", ".tgz")):
        return ("The download is a 7z, RAR or TAR archive, which the Files app can’t open. "
                "You’ll need an app that extracts it, then open the game file.")
    if "/raw/" in path:
        return "Download the game file from the repository’s file list."
    return None


# Platform names (and file extensions) that must never appear in the app's UI; see the
# app-store-compliance skill. Catalog titles use neutral names instead (e.g. "Snake", not
# "Snake DS"); each entry's page still links to the author's own release.
# "DS" is only a platform name in capitals ("words" is fine), so it's matched case-sensitively.
FORBIDDEN = (re.compile(r"DS"), re.compile(r"nintendo|\.nds", re.IGNORECASE))


def forbidden_fields(entry):
    """User-facing fields that mention a forbidden platform name."""
    fields = ("title", "author", "genre", "summary", "note")
    return [f for f in fields if any(p.search(entry.get(f) or "") for p in FORBIDDEN)]


def is_archive(path):
    """True if bsdtar can list the file (it sniffs .7z, .rar, .tar.gz, ...)."""
    result = subprocess.run(["bsdtar", "-tf", path], capture_output=True)
    return result.returncode == 0 and bool(result.stdout.strip())


def pick_game(names):
    """The game's .nds among an archive's members, skipping bundled menus/loaders."""
    skip = ("hbmenu", "boot", "loader", "menu", "__macosx")
    games = [n for n in names if n.lower().endswith(".nds") and not any(x in n.lower() for x in skip)]
    return sorted(games, key=len)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("work")
    parser.add_argument("--default-icon", action="append", default=[])
    args = parser.parse_args()
    os.makedirs(args.work, exist_ok=True)

    sources = json.load(open(SOURCES))
    bad = {e["id"]: forbidden_fields(e) for e in sources if forbidden_fields(e)}
    if bad:
        sys.exit(f"Platform names in user-facing text (use neutral wording): {bad}")
    files = {}
    for entry in sources:
        try:
            path = fetch(entry, args.work)
        except Exception as error:  # report and carry on
            print(f"  ! {entry['id']}: download failed ({error})", file=sys.stderr)
            path = None
        if path:
            files[path] = entry
        else:
            print(f"  - {entry['id']}: no game file (download it to {args.work}/{entry['id']}.nds)", file=sys.stderr)

    command = ["swift", "run", "-c", "release", "--package-path", PACKAGE, "clamshell-catalog",
               os.path.join(args.work, "verify")]
    for reference in args.default_icon:
        command += ["--default-icon", reference]
    output = subprocess.run(command + list(files), capture_output=True, text=True, check=True).stdout
    results = {r["file"]: r for r in (json.loads(l) for l in output.splitlines() if l.startswith("{"))}

    os.makedirs(APP_DIR, exist_ok=True)
    for name in os.listdir(APP_DIR):
        if name.startswith("homebrew-") and name.endswith(".png"):
            os.remove(os.path.join(APP_DIR, name))

    catalog = []
    for path, entry in files.items():
        result = results.get(os.path.basename(path))
        # Minimal text menus can trip the "nearly blank" heuristic; a recorded human review of
        # the screenshot ("manualCheck") overrides that one reason only.
        if result and not result["ok"] and result["reason"] == "screens nearly blank" and entry.get("manualCheck"):
            result["ok"] = True
        if not result or not result["ok"]:
            print(f"  ✗ {entry['id']}: {result['reason'] if result else 'not verified'}", file=sys.stderr)
            continue
        icon = False
        if result.get("icon") and not result.get("defaultIcon") and entry["licence"] in ICON_LICENCES:
            shutil.copyfile(result["icon"], os.path.join(APP_DIR, f"homebrew-{entry['id']}.png"))
            icon = True
        item = {k: entry[k] for k in ("id", "title", "author", "genre", "summary", "licence", "page")}
        note = entry.get("note") or download_note(entry.get("download", ""))
        if note:
            assert not forbidden_fields({"note": note}), note
            item["note"] = note
        item["icon"] = icon
        catalog.append(item)
        print(f"  ✓ {entry['id']}: {int(result['fps'])} fps, {result['colours']} colours, icon={icon}", file=sys.stderr)

    catalog.sort(key=lambda e: e["title"].lower())
    with open(os.path.join(APP_DIR, "homebrew-catalog.json"), "w") as out:
        json.dump(catalog, out, indent=2, ensure_ascii=False)
        out.write("\n")
    print(f"{len(catalog)} of {len(sources)} games in the catalog", file=sys.stderr)


if __name__ == "__main__":
    main()
