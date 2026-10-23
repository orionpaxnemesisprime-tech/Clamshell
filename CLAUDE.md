# Clamshell

An open-source (**GPLv3**) native Swift/SwiftUI emulator for a dual-screen handheld, built for
the foldable **iPhone Duo**. The core is **melonDS** (GPLv3, C++), run as an **interpreter
only (no JIT)**, because the App Store forbids JIT.

## Architecture

```
SwiftUI shell (MainActor)   layouts per fold posture · settings · library · licences
  │  input snapshot / command queue (Mutex/Atomic)         ▲ latest frame slot (atomic)
  ▼                                                        │
Emulation thread (dedicated Thread, .userInteractive)  ── RunFrame @ 59.8261 Hz
  │  EmulatorCore (Packages/ClamshellCore; nonisolated, not Sendable)
  ▼
C header ClamshellBridge.h ── the only API Swift sees (no C++ interop)
  ▼
ClamshellBridge.xcframework ── Core/Bridge (facade + melonDS::Platform::*) + melonDS core
                               + teakra; static, ENABLE_JIT=OFF, no Qt/SDL/OpenGL
```

Runtime pieces in `Packages/ClamshellCore`:
- `EmulationSession`: emulation thread, pacing and input snapshot.
- `FrameStore`: triple buffer.
- `AudioRingBuffer`: SPSC ring.
- `AudioOutput`.
- `ScreenLayout`: posture geometry and touch mapping.
- `GameLayout`/`ControlsLayout`: on-screen controls.
- `InputRouter`/`InputMapping`: touch, gamepad and keyboard input.
- `SaveStore`: battery saves.
- `StateStore`: save-state slots.
- `MicrophoneInput`.
- `HingeLidTracker`: fold-to-lid hysteresis.
- `RumbleOutput`: Rumble Pak to Core Haptics.

App pieces in `Clamshell/`:
- `Rendering/`: Metal `DualScreenRenderer` and the touch-handling `GameMTKView`.
- `Views/`: library, the game view with posture detection, save states, Settings, and About.
- `Emulation/EmulatorModel`.

Repo layout:
- `Vendor/melonDS`: pinned submodule.
- `Core/Bridge`: C++ bridge and its CMake build.
- `Scripts/`: `build-core.sh` and `make-test-rom.py`.
- `Packages/ClamshellCore`: Swift API, tests and test ROMs.
- `Clamshell/`: the app.

- **Video**: Metal draws two 256x192 BGRA screens from a triple-buffered frame store. The
  renderer never waits on the core.
- **Audio**: SPU output → lock-free SPSC ring → `AVAudioSourceNode`. Mic input:
  `AVAudioEngine` tap → s16 mono ~47.6 kHz ring → `Platform::Mic_ReadInput`.
- **Input**:
  - touch and Apple Pencil map to the touch screen through the active layout's
    bottom-screen rect;
  - controls come from `GameController`, on-screen buttons and keyboard;
  - Core Haptics for button feedback and rumble.
- **Persistence**: battery saves keyed by ROM SHA-1 (debounced atomic writes), versioned save
  states, and FreeBIOS plus generated firmware by default. Users may import their own
  BIOS/firmware.

## Fold layouts

All geometry comes from `GeometryReader`/`onGeometryChange`. Never hardcode device sizes.

| Posture | Layout |
|---|---|
| Half-folded ("clamshell") | Top screen above the fold, touch screen below. Fold rect from `reservedRegions(kind: .division)` (iOS 27.1+) |
| Fully open | Inner display, stacked with a gap or side by side (user choice) |
| Closed / cover screen | Both screens stacked on the wide, short outer display; aspect-fit fallback; avoid the camera `.occlusion` region |

- Folding resizes the scene without relaunching, so keep emulator state above
  size-class branches.
- Hinge → lid close (`onHingeChange`, iOS 27.1+) is **opt-in with hysteresis**, plus a manual
  lid button.

## Targets and toolchain

- **iOS 27** deployment, iPhone (iPhone Duo first). **Swift 6.2** language level: Swift 6
  language mode, strict concurrency, approachable concurrency, `MainActor` default isolation.
  Don't use language features newer than Swift 6.2, even though the installed toolchain is
  Swift 6.4.2 (Xcode 27.2). Where a skill (e.g. swiftui-pro, which says "Swift 6.4 or
  later") disagrees, this file wins.
- Prefer SwiftUI. Use UIKit only where needed (Metal view host, precise touch/Pencil
  handling) and wrap it.
- The project uses Xcode 27's `Clamshell.xcodeproj/project.xcproj` format. Scheme:
  `Clamshell`.
- Project settings: `SWIFT_VERSION = 6.0` and `IPHONEOS_DEPLOYMENT_TARGET = 27.0`. Guard
  iOS 27.1 fold/hinge APIs with `#available`. `TARGETED_DEVICE_FAMILY = 1,2`: iPhone Duo is
  the primary target, and iPad is supported too (decided 2026-10-19). Layouts must also work
  in resizable iPad windows.

## Licensing (summary; full rules in the `app-store-compliance` skill)

- After changing any dependency or `THIRD_PARTY_LICENSES`, run `Scripts/update-licenses.sh`. It
  regenerates the full licence texts bundled in the app (`Clamshell/Licenses`, shown in About).
  `--check` fails if they are stale.
- `AboutView.sourceRepository` must be set to the public repo before any release.

- The whole app is GPLv3. Keep `LICENSE`, `THIRD_PARTY_LICENSES` and an in-app licence
  screen, and tag every shipped build in the public repo.
- Only GPLv3-compatible dependencies. Check the licence before adding anything.
- Never use Nintendo ROMs, BIOS or firmware, or Nintendo names, logos or console likeness.
  Content is FreeBIOS, permitted homebrew, or user-imported files only. Show the
  non-affiliation disclaimer.
- No JIT and no writable+executable memory.

## Which skill to load

| Task | Skill / tool |
|---|---|
| Core, bridge, threading, Metal upload, audio/mic, touch mapping, hinge/lid, saves, BIOS, core tests | `ds-emulation` (project) |
| Any dependency, asset, test ROM, BIOS/ROM import, naming/icon/UI copy, screenshots, entitlements, release | `app-store-compliance` (project), **always** |
| SwiftUI views, layouts, iPhone Duo resizability and fold APIs | `swiftui-pro` |
| Threads, actors, `Sendable`, Swift 6 isolation errors | `swift-concurrency` |
| Writing or migrating tests (Swift Testing) | `swift-testing-expert` |
| SwiftUI performance (view updates, hangs) | `swiftui-performance-audit`. For the emulator hot path use `ds-emulation` and Instruments |
| Accessibility audits | `swiftui-accessibility-auditor`, `uikit-accessibility-auditor` |
| TestFlight, metadata, submission via `asc` | `asc-*` skills. The `asc` CLI isn't installed and needs App Store Connect credentials, so ask first. Submissions and publishes are outward-facing: confirm every time |
| Build, test, run on simulator, screenshots, logs | `mobilebuildmcp` MCP server (`.mcp.json`) |

## Build and test

- First checkout:
  1. `git submodule update --init`
  2. `brew install cmake ninja`
  3. `xcodebuild -downloadComponent MetalToolchain` (Xcode 27 ships it separately; the app's
     shaders need it)
  4. `Scripts/build-core.sh`

  Re-run the build script after changing `Core/Bridge` or `Vendor/melonDS`.
- Core tests (headless Swift Testing, homebrew ROMs built from source; see `ds-emulation`):
  - Host: `cd Packages/ClamshellCore && swift test`
  - iOS Simulator: `xcodebuild test -scheme ClamshellCore -destination 'platform=iOS Simulator,name=iPhone Duo'`
    (run in `Packages/ClamshellCore`)
- App, through MobileBuildMCP (preferred for agents) or directly:
  `xcodebuild -project Clamshell.xcodeproj -scheme Clamshell -destination 'platform=iOS Simulator,name=iPhone Duo' build`

### iPhone Duo simulator notes

- **Displays.** The simulator has two displays. Take screenshots with
  `xcrun simctl io <udid> screenshot --display=3 out.png` for the inner display. Display 1 is
  the outer display and is black while the device is open.
- **UI automation.** AXe (bundled with MobileBuildMCP) injects taps into the primary
  display, so it can't reach the inner display.
  - To reach a game screen, copy a test ROM into the app container's `Documents/Games/`
    (`xcrun simctl get_app_container <udid> com.foldingduo.Clamshell data`).
  - Then launch with the DEBUG-only argument `-ClamshellAutoplay "<game name>"`.
- **Posture.** Folding and rotation need manual Device Hub interaction. Ask the user to check
  the clamshell and closed layouts.
- **Touch automation.** For anything touch-driven, use a single-display simulator
  (e.g. iPhone 18 Pro).
  - Run AXe calls one at a time and read their output. Back-to-back calls silently drop
    events, and it sometimes fails with "Timed out creating the simulator remote automation
    session".
  - Touch coordinates are window points; views are offset by the navigation bar.
- **Keyboard and gamepad.**
  - AXe `key` events don't reach `GCKeyboard`, so keyboard mapping is covered only by unit
    tests. Check it by hand with Simulator › I/O › Keyboard.
  - The Simulator always reports a virtual "Gamepad [MFi]". That's why on-screen controls hide
    only after a gamepad is actually used.
- **Shared simulator.** The user may be interacting with the Duo simulator. Run unattended
  test suites on another simulator.
- **Crashes.** Check `~/Library/Logs/DiagnosticReports/Clamshell-*.ips`, or the
  SpringBoard/FrontBoard "Process exited" log. A launch that drops to the home screen is a
  crash, even when no alert appears.

### App resources

- **App icon:** generated by `swift Scripts/make-app-icon.swift
  Clamshell/Assets.xcassets/AppIcon.appiconset` (light, dark and tinted). It's an original
  scallop shell; never a hinged two-screen device.
- **Extra Info.plist keys** (document types, our exported `com.foldingduo.clamshell.game` UTI
  for `.nds`) live in `Config/Info.plist`. It's merged with the generated plist via
  `INFOPLIST_FILE` and kept out of `Clamshell/` so it isn't copied as a resource.
- **Find Homebrew** (link-out catalog):
  - Data is `Clamshell/Homebrew/homebrew-catalog.json` plus icons, generated by
    `Scripts/build-homebrew-catalog.py` from `Scripts/homebrew/sources.json`.
  - Games are verified with the package's `clamshell-catalog` tool.
  - Rules are in the app-store-compliance skill.
- **Tip jar:** `Clamshell/Support/TipJar.swift` (RevenueCat, consumable tips that unlock
  nothing), shown in Settings only when the `REVENUECAT_API_KEY` build setting holds a
  RevenueCat public SDK key (`appl_…`, or `test_…` for RevenueCat's Test Store). Products:
  `com.foldingduo.Clamshell.tip.{small,medium,large}`. Use the RevenueCat MCP for dashboard
  setup; privacy rules are in the app-store-compliance skill.
- **Resume:** the hidden save-state slot 99, written on background and on close; the library
  shows it as Continue.

### Project file (Xcode 27 `project.xcproj` format)

The format is undocumented, so don't hand-write new structures. Instead:

1. Convert a scratch copy to legacy format: `xcodebuild -project … -convert-project "Xcode 16.0"`.
2. Edit the familiar `project.pbxproj`, and check that it builds.
3. Convert back with `-convert-project "Xcode Project"`, and copy the result in.

`xcodebuild -list` validates the file and names the bad JSON path. The local package is
linked through `packages` plus the target's `package-product-members`.

## Agent tooling provenance

Each entry below was reviewed on 2026-10-19. When updating any of them, re-review the diff
first.

- **Plugins** (project scope, `.claude/settings.json`):
  - `swiftui-pro@swiftui-agent-skill` (twostraws)
  - `swift-concurrency@swift-concurrency-agent-skill` (AvdLee)
  - `swift-testing-expert@swift-testing-agent-skill` (AvdLee)
  - `asc@rorkai` (rorkai, formerly rudrankriyam)
- **Copied skills** in `.claude/skills/`, each with its upstream LICENSE:
  - `swiftui-accessibility-auditor` and `uikit-accessibility-auditor` (rgmez, tracked in
    `skills-lock.json`)
  - `swiftui-performance-audit` (Dimillian/Skills @ `05ba982`, Codex-only `agents/` folder
    removed)
- **MCP**: `mobilebuildmcp@2.7.1` (getsentry/MobileBuildMCP, formerly XcodeBuildMCP), pinned,
  with Sentry telemetry disabled through `MOBILEBUILDMCP_SENTRY_DISABLED=true`.
