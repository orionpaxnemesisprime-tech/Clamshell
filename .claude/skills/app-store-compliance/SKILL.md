---
name: app-store-compliance
description: Hard legal and App Store rules for Clamshell - no Nintendo ROMs, BIOS or firmware; no Nintendo trademarks or console likeness; GPLv3 obligations and dependency licence checks; no JIT or writable+executable memory; App Review 4.7, 5.2 and privacy requirements. Use before adding any dependency, asset, test ROM, BIOS/firmware handling, ROM import or download code, app name/icon/UI copy, screenshots or metadata, entitlements, or a release/submission.
---

# App Store and licence compliance (hard rules)

These rules are **not negotiable**. If a request conflicts with one, stop and tell the user
which rule it breaks; don't look for a workaround. If something is ambiguous, treat it as
forbidden until the user decides.

## 1. Game content, BIOS and firmware

- **Never** bundle, embed, download, link to, generate URLs for, or help locate commercial
  Nintendo ROMs or Nintendo BIOS/firmware dumps. This covers the app, tests, CI, sample data,
  screenshots, docs, issue reproductions and commit history.
- What may ship:
  - **FreeBIOS** (from melonDS; BSD-2, © Gilead Kutnick) and melonDS's generated firmware;
  - **homebrew** whose author gave written permission to redistribute. Keep the permission
    (link or copy) in `THIRD_PARTY_LICENSES` next to the ROM's entry;
  - ROMs built from source in this repo.
- **User-imported files only** for anything else, through the system document picker
  (`fileImporter` / `UIDocumentPickerViewController`). The app must not:
  - contain a ROM or BIOS catalogue, search, store, or "where to get games" link;
  - hash-match files against known Nintendo dumps (no "detect your BIOS" by fingerprint;
    validate size and structure only);
  - upload, sync or share imported BIOS/firmware/ROMs to any server. That includes analytics
    and crash reports: never attach file contents, names or hashes.
- Imported BIOS/firmware stays in the app container and can be deleted from Settings.
- **Find Homebrew (link-out only)** — decided 2026-10-19: Clamshell may *link* to original
  homebrew on its author's own release page (`HomebrewGame.catalog` in
  `Clamshell/Views/FindHomebrewView.swift`), but never hosts, downloads or redistributes it
  (no written permissions were obtained, so in-app downloads are not allowed). Each entry
  must be:
  - original work, not based on another company's games, characters or trademarks, and with
    no themes that promote alcohol, drugs or tobacco (App Review 1.4.3);
  - under a published licence that allows download;
  - linked to its individual project or release page, never to a list or site that also
    carries ports or ROMs of others' games;
  - verified to boot in Clamshell;
  - described in our own neutral words, with no third-party trademarks. Titles drop any
    platform suffix or prefix ("Snake", not "Snake DS"); the builder refuses "DS",
    "Nintendo" or ".nds" in any user-facing field.

  The catalog is compiled into the app so App Review sees exactly what is linked.
- **Catalog workflow:**
  1. Add the game to `Scripts/homebrew/sources.json`.
  2. Run `python3 -I Scripts/build-homebrew-catalog.py <scratch-dir> --default-icon <ref>...`.
     It downloads to scratch only and boots each game in the `clamshell-catalog` verifier.
  3. Review the screenshots with `clamshell-catalog --sheet`. They must be real title or
     menu screens: no error screens, no photos of real people, nothing objectionable.
  4. Use `manualCheck` only to override the "nearly blank" heuristic, after a human has
     reviewed the screenshot.
- **Icons:**
  - A game's banner icon is bundled only if its licence clearly allows redistribution.
  - **Never bundle SDK placeholder icons** (BlocksDS, devkitPro…): they depict console
    hardware. Pass each as `--default-icon` (keep them outside the repo) so they're rejected.
- **Downloads:** only the author's normal free download. Don't automate itch.io
  name-your-price or purchase flows; leave those games out or have a person verify them.

## 2. Trademarks and trade dress

- Never use "Nintendo", "DS", "DSi", "3DS", "Nintendo DS", "NDS" or any Nintendo game or
  character name in any of these:
  - app name, subtitle or keywords;
  - bundle display name or icon;
  - UI strings, in-app screenshots or App Store screenshots;
  - marketing or the website.
  Neutral functional wording is fine: "dual-screen handheld", "touch screen", "top/bottom
  screen". `.nds` may appear only as a file-type extension in the document picker.
- No Nintendo logos, fonts, button glyphs styled after Nintendo hardware, or the original
  console's shell design or colours in icons, skins or controller overlays. Skins are
  original artwork.
- App Store screenshots and previews show **only homebrew** or original content, with
  permission recorded.
- Show this **non-affiliation disclaimer** in Settings › About and in the App Store
  description: "Clamshell is not affiliated with, endorsed by, or sponsored by Nintendo.
  All trademarks belong to their respective owners. Clamshell does not include any games;
  you must supply software you have the right to use."

## 3. GPLv3 (the whole app)

- Clamshell is GPLv3 because melonDS is GPLv3. Every file we write is GPLv3-licensed.
- Keep:
  - the full GPLv3 text in `LICENSE` at the repo root;
  - `THIRD_PARTY_LICENSES`, updated in the **same commit** that adds, removes or bumps any
    dependency, vendored code, font, asset or test ROM. Each entry records name, version or
    commit, licence and source URL.
- Bundled texts: `Scripts/update-licenses.sh` regenerates `Clamshell/Licenses/*.txt` (GPL text,
  component list, and full third-party licence texts). Run it in the same commit as any
  dependency change. `--check` detects drift.
- In-app: Settings › Licenses shows the GPLv3 text, `THIRD_PARTY_LICENSES`, the disclaimer,
  and a link to the public source repository **and the exact tag** for this build.
- **Corresponding source**: every shipped build is tagged. The public repo at that tag
  contains everything needed to rebuild it, including build scripts, the pinned submodule
  commits and the melonDS patches. Don't ship from an untagged or private commit.
- **Dependency gate.** Before adding anything (Swift package, CocoaPod, vendored C/C++,
  font, image, sound, shader):
  1. Read its licence file, not just the package metadata.
  2. Allowed (GPLv3-compatible): GPLv3, GPLv3+, GPLv2-**or-later**, LGPLv3 (or LGPLv2.1+),
     MIT, BSD-2/3, ISC, zlib, Apache-2.0, Unlicense or CC0, MPL-2.0.
  3. Forbidden: GPLv2-**only**, CC-BY-NC/ND, proprietary or "free for non-commercial"
     licences, SDKs with closed binaries, and anything without a licence.
  4. Ask the user before adding any dependency with network access, analytics or ads.
     Default is none.
- Known risk to raise, not to resolve on your own: App Store terms impose restrictions that
  GPLv3 §10 forbids adding, and distributing GPL code on the App Store has been disputed
  before. Other GPL emulators built on melonDS do ship on the App Store, but before the first
  submission the maintainer should get confirmation from the melonDS copyright holders and,
  ideally, legal advice. If a task touches App Store submission, remind the user of this
  once.

## 4. No JIT, no writable+executable memory

- The core is built with `ENABLE_JIT=OFF` and run with `NDSArgs.JIT = std::nullopt`.
  Interpreter only.
- Never add:
  - `MAP_JIT`, or `mmap`/`mprotect` with `PROT_EXEC`;
  - `vm_protect` with execute permission;
  - `pthread_jit_write_protect_np`;
  - the `com.apple.security.cs.allow-jit` entitlement (or any `cs.*` entitlement);
  - `dlopen` of downloaded code;
  - JavaScriptCore or WebKit used to run emulator code.
- No downloadable code or scripts that change app behaviour (Guideline 2.5.2). Cheat-code
  databases are data, and are user-imported only.
- CI check: fail the build if the linked binary references `MAP_JIT`/`mprotect` with exec
  flags, or contains `ARMJIT` symbols.

## 5. App Review guidelines

- **4.7 (mini apps, games, emulators)**: retro console emulators are permitted. The
  developer is responsible for everything the app offers, and must comply with the law
  and §5 for all of it. That's why there is no bundled or downloadable commercial content
  (rule 1). Any future game download feature would be limited to content we have rights to,
  and needs the user's sign-off first.
- **5.2 (intellectual property)**: no third-party trademarks, copyrighted assets or
  look-alike trade dress (rule 2). Don't suggest the app is endorsed by anyone.
- **2.5.2**: no executing downloaded code (rule 4).
- **Metadata (2.3)**: the description, screenshots and keywords follow rule 2. No
  "play your favourite Nintendo games".

## 6. Privacy

- Purpose strings:
  - `NSMicrophoneUsageDescription` (game mic input), requested only when a game first opens
    the mic;
  - `NSCameraUsageDescription` only if the DSi camera is ever supported (not in v1).
- `PrivacyInfo.xcprivacy` declares the required-reason APIs we use: file timestamps,
  `UserDefaults`, and system boot time if `mach_absolute_time` is used for frame pacing.
  Keep it current whenever such an API is added.
- No tracking, no third-party analytics or ads, and no account. The App Privacy "nutrition
  label" is "Data Not Collected" unless the user explicitly approves a change.
- Microphone audio is processed in memory only. It is never recorded to disk or sent anywhere.

## Pre-submission checklist

1. `LICENSE`, `THIRD_PARTY_LICENSES` and the in-app licence screen are current.
2. The build tag is pushed publicly, and the source link in the app points at it.
3. No Nintendo names or likeness in the name, icon, UI, screenshots or metadata;
   the disclaimer is present.
4. No ROMs or BIOS in the bundle (inspect the `.app`), and no download or search URLs.
5. No JIT entitlements or symbols. The privacy manifest and purpose strings are complete.
6. The melonDS copyright-holder confirmation is on record (see §3).
