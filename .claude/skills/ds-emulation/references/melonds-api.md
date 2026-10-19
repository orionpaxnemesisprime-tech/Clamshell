# melonDS frontend API cheat sheet

These notes were checked against melonDS commit `906e9eb` (2026-08-23). They are a map to the
source, not a substitute for it. Re-read the headers after bumping the submodule.

## Construction (`src/Args.h`)

```cpp
melonDS::NDSArgs args;                 // defaults: FreeBIOS ARM9/ARM7, generated firmware (Firmware{0})
args.JIT = std::nullopt;               // REQUIRED for Clamshell (also build with ENABLE_JIT=OFF)
args.OutputSampleRate = 48000.0;       // match AVAudioSession
args.Interpolation = AudioInterpolation::None;  // or Linear/Cosine/Cubic/SNESGaussian
// args.ARM9BIOS / args.ARM7BIOS / args.Firmware: replace only with user-imported files
auto nds = std::make_unique<melonDS::NDS>(std::move(args), /*userdata*/ bridgePtr);
```

`DSiArgs` exists but needs Nintendo DSi BIOS and NAND, so it is out of scope.

## Lifecycle (`src/NDS.h`)

| Call | Notes |
|---|---|
| `NDSCart::ParseROM(std::unique_ptr<u8[]>&&, u32 len, void* userdata, std::optional<NDSCartArgs>&&)` | `NDSCartArgs.SRAM` = existing save, `.SDCard` for homebrew DLDI |
| `nds->SetNDSCart(std::move(cart))` / `EjectCart()` | |
| `nds->Reset()` | |
| `NeedsDirectBoot()` → `SetupDirectBoot(romName)` | Always true with FreeBIOS |
| `nds->Start()` | |
| `u32 RunFrame()` | Runs one emulated frame (returns `GPU.TotalScanlines`; 0 means no frame was produced) |
| `Stop(Platform::StopReason)` | `Platform::SignalStop` is called when the core stops itself |
| `IsRunning()` | |

## Input

`SetKeyMask(u32)` takes the key bits (see GBATEK KEYINPUT/EXTKEYIN and the Qt frontend for
polarity). Also `TouchScreen(u16 x, u16 y)`, `ReleaseScreen()`, `SetLidClosed(bool)` and
`IsLidClosed()`.

## Video (`src/GPU.h`)

`bool GetFramebuffers(void** top, void** bottom)` returns `true` with RAM pointers for the
soft renderer. Each buffer is 256x192 `u32`, uploaded by the Qt frontend as `GL_BGRA` /
`GL_UNSIGNED_BYTE`, so in Metal use `.bgra8Unorm`.

`SetRenderer(std::unique_ptr<Renderer>&&)` takes `SoftRenderer`. Its 3D part has
`SetThreaded(bool)`.

## Audio (`src/SPU.h`)

`int ReadOutput(s16* data, int samples)` gives interleaved stereo. There is also
`GetOutputSize()`, `SetOutputSampleRate(double)`, `SetInterpolation(...)` and
`SetDegrade10Bit(...)`. The internal SPU clock is `16756991` Hz.

## Save states (`src/Savestate.h`)

`Savestate(void* buffer, u32 size, bool save)` or `Savestate(u32 initial_size)`, then
`nds->DoSavestate(&st)`. Check `st.Error`.

## Save memory (`src/NDSCart.h`)

`NDSCartSlot::GetSaveMemory()`, `GetSaveMemoryLength()` and `SetSaveMemory(const u8*, u32)`.

## Platform callbacks the bridge implements (`src/Platform.h`)

- **Lifecycle**: `SignalStop`.
- **Files**: `OpenFile`, `OpenLocalFile`, `GetLocalFilePath`, `FileRead`, `FileWrite`,
  `FileSeek`, `FileLength`, `CloseFile`, and the rest of the file functions. Map these to the
  app container only.
- **Logging**: `Log(LogLevel, fmt, ...)`. Send to `os.Logger`, and never log file paths that
  contain user names.
- **Threads and sync**: `Thread_*`, `Semaphore_*`, `Mutex_*`, `Sleep`, `GetMSCount`,
  `GetUSCount`. Implement with pthread/os primitives.
- **Saves**: `WriteNDSSave(savedata, savelen, writeoffset, writelen, userdata)`,
  `WriteGBASave`, `WriteFirmware`, `WriteDateTime`.
- **Mic**: `Mic_Start`, `Mic_Stop`, and `Mic_ReadInput(s16* data, int maxlength, void*)`.
  Data is s16 mono at ~47.6 kHz.
- **Stubs**: implement as no-ops returning 0/false for `MP_*` and `Net_*` (local multiplayer
  and Wi-Fi, not in v1), `Camera_*` (DSi), `AAC_*` (DSi), `Addon_*` (rumble pak and so on;
  rumble may later map to Core Haptics) and `DynamicLibrary_*`. iOS can't load dynamic
  libraries at runtime, so `DynamicLibrary_Load` must return `nullptr`.
