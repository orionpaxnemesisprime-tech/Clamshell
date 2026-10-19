---
name: ds-emulation
description: Clamshell emulation-core guidance - building melonDS as an iOS arm64 static library with JIT off, Swift/C++ interop with the core, the dedicated emulation thread, frame pacing, audio/mic ring buffers, Metal upload of the two 256x192 screens, touch/Pencil mapping per fold layout, hinge-to-lid mapping, saves/save states, FreeBIOS and user-imported BIOS/firmware, and headless Swift Testing of homebrew ROMs. Use when touching anything under the emulator core package, the core bridge, rendering, audio, input, persistence of game data, or core tests.
---

# DS emulation core (melonDS on iOS)

Load `app-store-compliance` as well whenever the change touches BIOS/firmware, ROM import,
bundled test content, or third-party code. Its rules override anything here.

## References

- **GBATEK** - the hardware reference for DS/DSi: https://problemkaputt.de/gbatek.htm
  Use it for touchscreen (TSC) semantics, key bits (KEYINPUT/EXTKEYIN), lid/sleep behaviour,
  timing, and the SPI firmware layout. Cite the section when you rely on a hardware detail.
- **melonDS** (GPLv3): https://github.com/melonDS-emu/melonDS - `BUILD.md`, `src/Args.h`,
  `src/NDS.h`, `src/Platform.h`. The frontend API notes in
  [references/melonds-api.md](references/melonds-api.md) were checked against commit `906e9eb`
  (2026-08-23). Re-verify signatures after bumping the pinned melonDS revision.
- **Qt frontend as prior art**: `src/frontend/qt_sdl/EmuThread.cpp` (frame limiter, run loop),
  `EmuInstanceAudio.cpp` (audio/mic resampling), `Screen.cpp` (framebuffer upload). It is GPLv3
  like Clamshell, so adapting it is allowed with attribution, but never link Qt or SDL.

### melonDS source layout (what matters to us)

| Path | Contents | Use in Clamshell |
|---|---|---|
| `src/NDS.*`, `src/DSi.*` | `melonDS::NDS` machine object, run loop, input | NDS only; DSi mode needs Nintendo DSi BIOS/NAND, so it's out of scope |
| `src/Args.h` | `NDSArgs` - BIOS, firmware, JIT, audio, renderer | Construct the core from this |
| `src/Platform.h` | Callbacks the frontend must implement (files, threads, saves, mic, log) | Implement in our C++ bridge |
| `src/ARMInterpreter*`, `ARM.*`, `CP15.cpp` | CPU interpreter | Always used (JIT off) |
| `src/ARMJIT*`, `ARMJIT_A64/` | JIT recompiler | **Never compiled** |
| `src/GPU*.cpp`, `GPU3D_Soft.*`, `GPU_Soft.*` | 2D/3D software renderer | Our renderer |
| `src/GPU*_OpenGL*`, `GPU3D_Compute*`, `OpenGL_shaders/` | GL renderers | Excluded (`ENABLE_OGLRENDERER=OFF`) |
| `src/SPU.*`, `src/Mic.*` | Sound and microphone | Audio bridge |
| `src/NDSCart.*`, `src/GBACart.*` | Cartridge parsing, save memory | ROM loading, saves |
| `src/SPI_Firmware.*`, `FreeBIOS.*` | Firmware, FreeBIOS (BSD-2, Gilead Kutnick) | Defaults |
| `src/Savestate.*` | Save-state serializer | Save states |
| `src/net/`, `src/frontend/` | Wi-Fi backends (slirp/pcap), Qt/SDL UI | Not built |
| `src/teakra/` | DSi DSP; static-linked into `core` by CMake | Link the resulting `libteakra.a` |

## Building the core for iOS

The rules are fixed:

- **JIT OFF.** melonDS defaults `ENABLE_JIT=ON` on Apple arm64, so pass `-DENABLE_JIT=OFF`
  explicitly. Also set `NDSArgs.JIT = std::nullopt` in code. As a belt-and-braces check, the
  build script must fail if any `ARMJIT*` object or a `MAP_JIT`/`mprotect(PROT_EXEC)` symbol
  ends up in the archive.
- **No Qt/SDL frontend**: `-DBUILD_QT_SDL=OFF`. **No OpenGL**: `-DENABLE_OGLRENDERER=OFF`.
  **No GDB stub**: `-DENABLE_GDBSTUB=OFF`.
- Static only. Build the `core` target (`add_library(core STATIC ...)` in `src/CMakeLists.txt`).

Build it with **`Scripts/build-core.sh [Release|Debug]`** (needs cmake and ninja from
Homebrew). The script:

- configures `Core/Bridge/CMakeLists.txt`, which pulls in `Vendor/melonDS` and forces the
  forbidden options off (JIT, Qt/SDL, OpenGL, GDB stub, and LTO, since LLVM bitcode in
  archives is fragile);
- builds iOS device, iOS Simulator and macOS (host-test) arm64 slices;
- merges `libClamshellBridge.a`, `libcore.a` and `libteakra.a` with `libtool`;
- **fails if any `ARMJIT`/`JitBlock` symbol is defined, or `mprotect`, `vm_protect`,
  `pthread_jit_write_protect_np` or `sys_icache_invalidate` is referenced**. A JIT-on control
  build was verified to trip it;
- writes `Packages/ClamshellCore/Artifacts/ClamshellBridge.xcframework` (gitignored, about
  30 MB).

Notes:

- Re-run the script after any change under `Core/Bridge/` or `Vendor/melonDS`.
- melonDS is a **git submodule pinned to a commit** (currently `906e9eb`). Never track
  `master`. Record the commit in `THIRD_PARTY_LICENSES`.
- Keep Clamshell patches to melonDS minimal, as a patch series under `Vendor/patches/`, and
  upstream them where possible.
- The build script lives in the repo (for example `Scripts/build-melonds.sh`) and is
  reproducible, because GPL "corresponding source" includes the scripts used to build.

## Swift / C++ interop (as built)

- Swift never sees C++. `Core/Bridge/` compiles inside the static library: `Bridge.cpp`
  (owns `melonDS::NDS`) and `Platform.cpp` (every `melonDS::Platform::*` function). It
  exposes a **plain C header**, `Core/Bridge/include/ClamshellBridge.h`, as module
  `ClamshellBridge`. Swift imports it with no `.interoperabilityMode(.Cxx)` anywhere.
- To add a capability:
  1. extend the C header (plain types only: ints, pointers plus length, C enums and structs);
  2. implement it in `Bridge.cpp`;
  3. wrap it in `Packages/ClamshellCore/Sources/ClamshellCore/EmulatorCore.swift`;
  4. run `Scripts/build-core.sh`.
- Callbacks into Swift go through `ClamshellCoreCallbacks` (C function pointers plus a
  `context`). `EmulatorCore` sets `context` to an unretained `Unmanaged` pointer to itself,
  and the core never outlives it. `Platform::Log` has no per-instance userdata, so logging
  uses the process-wide `clamshell_set_log_handler`.
- C++ exceptions must not cross the C boundary. Catch inside the bridge and return a status.
- `Bridge.cpp` contains `#error` if `JIT_ENABLED` is defined.

## Threading model

- The core runs on **one dedicated `Thread`** at `.userInteractive` QoS, never on the Swift
  concurrency cooperative pool. The run loop blocks and would starve the pool.
- Everything melonDS touches (`RunFrame`, `TouchScreen`, `SetKeyMask`, `SetLidClosed`,
  `DoSavestate`, cart load/eject, and `ReadOutput` unless it's audio-pulled) happens on that
  thread.
- Other threads talk to it through:
  - an input snapshot (key mask, touch point, lid flag) in a `Synchronization.Mutex`/`Atomic`,
    read once per frame;
  - a command queue (pause, reset, save state, load state, stop) drained between frames.
- Swift 6 strict concurrency: the project's default actor isolation is `MainActor`, so mark the
  core wrapper and its thread entry `nonisolated`. The wrapper is deliberately not `Sendable`;
  only the snapshot and queue types are. Don't paper over this with `@unchecked Sendable`.
- Pause the thread on `scenePhase` background. Flush saves first.

## Frame pacing (~59.83 Hz)

- The target is 59.8260982880808 Hz (`INTERNAL_FRAME_RATE` in the Qt frontend), which is
  16.7151 ms per frame.
- Use a deadline loop on `ContinuousClock` or `mach_absolute_time`, carrying the accumulated
  error forward like `EmuThread.cpp`'s `frameLimitError`. Sleep until close to the deadline,
  then do a short spin. If the core falls more than about 3 frames behind, reset the deadline
  instead of fast-forwarding.
- Display runs at the panel rate. Render with `CAMetalDisplayLink` or `MTKView`, setting
  `preferredFrameRateRange` to 60 so ProMotion doesn't waste power. Display and emulation
  clocks drift, so the renderer shows the **latest completed** frame and never waits for one.
- Optionally offer audio-driven sync (let the ring buffer fill level nudge the frame deadline).
  Fast-forward and slow-motion scale the deadline only.

## Video: two 256x192 screens to Metal without blocking

- After `RunFrame()`, call `GetFramebuffers(&top, &bottom)` (soft renderer → RAM buffers,
  returns `true`). Each buffer is 256x192 `u32`. The Qt frontend uploads them as `GL_BGRA`,
  so use `MTLPixelFormat.bgra8Unorm` and force alpha to 1 in the shader.
- Use a **triple buffer** of frame slots, each holding top and bottom. The emu thread
  `memcpy`s into a free slot and publishes its index atomically. The renderer takes the newest
  published slot. Neither side waits on the other.
- On Apple silicon, back each slot with a `.storageModeShared` `MTLBuffer` and create
  linear textures over it (`makeTexture(descriptor:offset:bytesPerRow:)`), or use
  `replace(region:)` into per-slot textures. Never write a texture the GPU may still be
  reading. Retire slots in the command buffer's completion handler.
- Draw both screens in one render pass. Use nearest sampling at integer scale and optional
  filters at fractional scale. Compute the destination rects in the layout code (see below),
  and feed the same rects to the touch mapper.
- Enable the soft renderer's threaded 3D (`SetThreaded(true)`) on devices with spare cores.
  Measure the effect with Instruments before making it the default.

## Audio

- Set `NDSArgs.OutputSampleRate` to the hardware rate from `AVAudioSession` (usually
  48000). `SPU::ReadOutput(s16*, samples)` gives interleaved stereo `s16`.
- Emu thread → **lock-free single-producer/single-consumer ring buffer** → an
  `AVAudioSourceNode` render block. The render block runs on a real-time thread, so it must
  not take locks, allocate, touch Swift actors, use ObjC messaging or log.
- Target about 3 frames of latency (~2400 frames at 48 kHz). On underflow, output silence and
  count it. To absorb clock drift, either use audio sync or resample by ±0.5% based on the
  ring fill level, as `EmuInstanceAudio.cpp` does.
- Use `AVAudioSession` category `.playback`, and switch to `.playAndRecord` only while the
  mic is active (see below). Handle interruptions and route changes by pausing the core.

## Microphone

- melonDS *pulls* mic samples: `Platform::Mic_Start/Mic_Stop`, then
  `Mic_ReadInput(s16* data, int maxlength, void*)` wants **signed 16-bit mono at ~47.6 kHz**
  (the frontend uses 47743.4659 Hz).
- Install a tap on `AVAudioEngine.inputNode` and convert with `AVAudioConverter` to s16 mono
  at that rate, into an SPSC ring. `Mic_ReadInput` drains whatever is available and returns
  the count; it must never block.
- Only request mic permission on the first `Mic_Start` (needs `NSMicrophoneUsageDescription`).
  If permission is denied, feed silence and provide a "blow" button (the Qt frontend has
  `mic_blow.h`).

## Input and touch mapping

- Keys: build the 12-bit key mask (A, B, Select, Start, Right, Left, Up, Down, R, L, X, Y).
  Bits are active-low, as in GBATEK KEYINPUT/EXTKEYIN; check `SetKeyMask`'s expectation
  before inverting. Sources are on-screen controls, `GameController` and keyboard. Merge them
  into the input snapshot.
- Touch: the layout code publishes the bottom screen's on-screen rect in view coordinates.
  - **Touch-down** counts only inside that rect.
  - **Drag** keeps tracking, clamped to `0...255` and `0...191`.
  - **Up or cancel** calls `ReleaseScreen()`.
  - Conversion: `dsX = Int((p.x - r.minX) / r.width * 256)`, and the same for y with 192,
    then clamp.
  - Only one touch drives the stylus. Ignore further fingers while it's down.
- Apple Pencil: `UITouch.type == .pencil` takes priority over a finger. The DS samples touch
  once per frame, so the latest position per frame is enough; coalesced touches help only for
  smoothing.
- Layouts. All rects come from `GeometryReader`/`onGeometryChange`; never hardcode device
  dimensions.
  - **Half-folded ("clamshell")**: top screen above the fold, touch screen below it. Get the
    fold from `reservedRegions(kind: .division)` (iOS 27.1+, check `isActive`) and keep both
    screens and all controls clear of it.
  - **Fully open**: both screens on the inner display, with a user choice between stacked
    with a gap and side by side.
  - **Closed / cover screen**: both screens stacked on the outer display. It is wide and short,
    so integer scaling may not fit; fall back to aspect-fit. Keep clear of
    `reservedRegions(kind: .occlusion)` (camera).
  - Folding resizes the scene without relaunching. Keep emulator state above any
    size-class-driven view branch.
- **Lid** → `SetLidClosed(bool)`. On iPhone Duo (iOS 27.1+), SwiftUI's `onHingeChange()`
  reports hinge angle (180 = open, 0 = closed) and status. Look up its exact signature in the
  SDK or the swiftui-pro `resizability.md` reference; don't guess it.
  - Map fold-to-lid **only when the user opts in** (default off). Closing the phone moves the
    app to the cover layout, and sleeping the game on every close would be wrong.
  - Use hysteresis: lid closed below about 10°, open above about 30°.
  - Always offer a manual lid toggle, because some games use lid close as a mechanic.

## Saves, save states, BIOS and firmware

- **Battery saves**: load into `NDSCartArgs.SRAM` before `ParseROM`. melonDS calls
  `Platform::WriteNDSSave(savedata, savelen, writeoffset, writelen, userdata)` on the emu
  thread. Copy the dirty range, then debounce the disk write (about 1 s) on a utility queue.
  Write atomically (temp file plus `replaceItemAt`). Also flush on background, ROM change and
  app termination.
- Key saves by the ROM's SHA-1 (not file name), and store them in the app container
  (Documents/Saves, exposed through Files). Provide import and export.
- **Save states**: run them only on the emu thread, between frames. Create a
  `Savestate(buffer, size, save)` and call `nds.DoSavestate(&st)`, then check `st.Error`.
  Prefix each state with a Clamshell header (magic, Clamshell version, melonDS commit, ROM
  SHA-1, timestamp, thumbnail). Refuse to load across mismatched ROMs or major versions.
- **BIOS and firmware**: the default is `NDSArgs` as-is, which is FreeBIOS ARM9/ARM7 plus
  generated firmware (`Firmware{0}`).
  - FreeBIOS can't boot the firmware menu, so always direct-boot
    (`NeedsDirectBoot()` → `SetupDirectBoot(romName)`).
  - A user can optionally import their own BIOS and firmware. Validate sizes only (ARM9
    4 KiB, ARM7 16 KiB, firmware 256/512 KiB), keep the files in the app container, never
    upload or sync them, and let the user delete them.
  - Never ship, download, or fingerprint-match Nintendo files (see `app-store-compliance`).

## Testing strategy (Swift Testing, headless)

- Tests drive the bridge with the soft renderer only: no Metal, no audio engine, no UI.
  Include a macOS slice in the XCFramework so the core suite runs with `swift test`. Run the
  iOS simulator suite through MobileBuildMCP or `xcodebuild test`.
- **Test ROMs**: use only open-source homebrew whose licence allows redistribution.
  - Prefer ROMs built **in this repo from source**:
    1. Write ARM assembly in `Packages/ClamshellCore/TestROMs/<name>/arm9.s` and `arm7.s`.
    2. Run `python3 -I Scripts/make-test-rom.py Packages/ClamshellCore/TestROMs/<name>
       Packages/ClamshellCore/Tests/ClamshellCoreTests/ROMs/<name>.nds`.
    3. Check in both the sources and the `.nds`.
  - The generator uses Xcode's clang. It rejects code with relocations and leaves the header
    logo zeroed.
  - Use BlocksDS/libnds when a test needs C, for example to drive the touchscreen controller
    from the ARM7.
  - Each ROM signals its result deterministically. `smoketest` writes `0xC1A55E11` at
    `0x02200000`, echoes KEYINPUT at `+4`, keeps a loop counter at `+8`, and draws known
    colours. Read these with `EmulatorCore.debugRead32`; direct boot leaves the ARM9 data
    cache off.
  - Don't name a test resource folder `Resources`: codesign rejects such iOS test bundles. Third-party CPU test ROMs (for example the armwrestler
  family) may be added only after confirming their licence. Record the licence in
  `THIRD_PARTY_LICENSES`.
- Test patterns:
  - boot, run N frames, assert the framebuffer hash or pixels;
  - `TouchScreen` at mapped coordinates, then assert the ROM's echoed coordinates;
  - key-mask round-trip;
  - save-write callback fires, and a reload restores the save;
  - save state → mutate → load state → identical framebuffer hash;
  - lid-close sleeps and wakes;
  - parameterized layout → touch-mapping tests (pure Swift, no core needed).
- Use `@Suite(.serialized)` for anything that owns a core instance, and add `.timeLimit`.
  Keep frame counts small; a test that needs more than a few seconds of emulated time belongs
  in a separate, tagged slow suite.
- Never use commercial ROMs in tests, CI, screenshots or bug reproductions.
