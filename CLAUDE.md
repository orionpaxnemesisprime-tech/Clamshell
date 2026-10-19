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
  iOS 27.1 fold/hinge APIs with `#available`. `TARGETED_DEVICE_FAMILY = 1,2` still includes
  iPad; whether to keep it is an open decision.

## Licensing (summary; full rules in the `app-store-compliance` skill)

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

- First checkout: `git submodule update --init`, `brew install cmake ninja`, then
  `Scripts/build-core.sh`. Re-run the script after changing `Core/Bridge` or `Vendor/melonDS`.
- Core tests (headless Swift Testing, homebrew ROMs built from source; see `ds-emulation`):
  - Host: `cd Packages/ClamshellCore && swift test`
  - iOS Simulator: `xcodebuild test -scheme ClamshellCore -destination 'platform=iOS Simulator,name=iPhone Duo'`
    (run in `Packages/ClamshellCore`)
- App, through MobileBuildMCP (preferred for agents) or directly:
  `xcodebuild -project Clamshell.xcodeproj -scheme Clamshell -destination 'platform=iOS Simulator,name=iPhone Duo' build`

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
