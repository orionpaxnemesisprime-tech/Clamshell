// Clamshell — C facade over the melonDS core.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Boot and save-state sequences follow melonDS's Qt frontend
// (src/frontend/qt_sdl/EmuInstance.cpp, GPLv3, (c) melonDS team).

#include "ClamshellBridge.h"
#include "BridgeInternal.h"

#include "Args.h"
#include "FATStorage.h"
#include "GBACart.h"
#include "frontend/mic_blow.h"
#include "GPU_Soft.h"
#include "NDS.h"
#include "NDSCart.h"
#include "Savestate.h"
#include "SPU.h"
#include "version.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <cstddef>
#include <memory>
#include <new>

#if defined(JIT_ENABLED)
#error "Clamshell must be built with ENABLE_JIT=OFF (App Store forbids JIT)."
#endif

using namespace melonDS;

// melonDS's NDS object embeds all of the console's memory (~32 MB). The system allocator can
// hand a freed block that large back without zeroing it, and some emulator state relies on
// starting at zero: after certain games, the *next* game in the same process booted to a
// black screen. Allocating the machine in zeroed memory makes every boot identical to a fresh
// launch. (Found while verifying the homebrew catalog; reproducible with a DSi-enhanced
// homebrew followed by any other game.)
struct NDSDeleter {
    void operator()(NDS *nds) const noexcept
    {
        nds->~NDS();
        std::free(nds);
    }
};

static_assert(alignof(NDS) <= alignof(std::max_align_t), "calloc can't align NDS");

struct ClamshellCore {
    ClamshellCoreCallbacks callbacks {};
    std::unique_ptr<NDS, NDSDeleter> nds;
    bool rumblePak = false;
};

void *clamshell_internal_callbacks_context(void *userdata, ClamshellCoreCallbacks **callbacks)
{
    auto *core = static_cast<ClamshellCore *>(userdata);
    *callbacks = core ? &core->callbacks : nullptr;
    return core ? core->callbacks.context : nullptr;
}

extern "C" {

ClamshellCore *clamshell_core_create(ClamshellCoreCallbacks callbacks, double audioSampleRate)
{
    auto core = std::make_unique<ClamshellCore>();
    core->callbacks = callbacks;

    // Defaults: FreeBIOS ARM9/ARM7 and generated firmware. Never Nintendo files here;
    // user-imported BIOS/firmware will be passed in explicitly later.
    NDSArgs args;
    args.JIT = std::nullopt;
    args.OutputSampleRate = audioSampleRate > 0 ? audioSampleRate : 48000.0;
    args.Interpolation = AudioInterpolation::None;

    void *memory = std::calloc(1, sizeof(NDS));
    if (!memory)
        return nullptr;
    core->nds.reset(new (memory) NDS(std::move(args), core.get()));
    core->nds->SetRenderer(std::make_unique<SoftRenderer>(*core->nds));
    return core.release();
}

void clamshell_core_destroy(ClamshellCore *core)
{
    if (!core) return;
    if (core->nds && core->nds->IsRunning())
        core->nds->Stop(Platform::StopReason::External);
    delete core;
}

void clamshell_core_set_context(ClamshellCore *core, void *context)
{
    core->callbacks.context = context;
}

ClamshellLoadResult clamshell_core_load_rom(ClamshellCore *core,
                                            const uint8_t *rom, uint32_t romLength,
                                            const uint8_t *save, uint32_t saveLength,
                                            const char *romName,
                                            const char *sdCardPath, uint64_t sdCardSize)
{
    if (!rom || romLength == 0)
        return ClamshellLoadResultInvalidROM;

    NDSCart::NDSCartArgs cartArgs {};
    if (save && saveLength > 0)
    {
        cartArgs.SRAM = std::make_unique<u8[]>(saveLength);
        std::memcpy(cartArgs.SRAM.get(), save, saveLength);
        cartArgs.SRAMLength = saveLength;
    }
    if (sdCardPath && *sdCardPath)
        cartArgs.SDCard = FATStorageArgs { sdCardPath, sdCardSize, false, std::nullopt };

    auto cart = NDSCart::ParseROM(rom, romLength, core, std::move(cartArgs));
    if (!cart)
        return ClamshellLoadResultInvalidROM;

    NDS &nds = *core->nds;
    if (nds.IsRunning())
        nds.Stop(Platform::StopReason::External);

    nds.SetNDSCart(std::move(cart));
    if (core->rumblePak)
        nds.SetGBACart(GBACart::LoadAddon(GBAAddon_RumblePak, core));
    nds.Reset();
    // FreeBIOS cannot boot the firmware menu, so always direct-boot.
    nds.SetupDirectBoot(romName ? romName : "game.nds");
    return ClamshellLoadResultOK;
}

void clamshell_core_set_rumble_pak(ClamshellCore *core, bool inserted) { core->rumblePak = inserted; }

void clamshell_core_start(ClamshellCore *core) { core->nds->Start(); }

void clamshell_core_stop(ClamshellCore *core)
{
    if (core->nds->IsRunning())
        core->nds->Stop(Platform::StopReason::External);
}

void clamshell_core_reset(ClamshellCore *core)
{
    NDS &nds = *core->nds;
    nds.Reset();
    if (nds.NDSCartSlot.GetCart())
        nds.SetupDirectBoot("game.nds");
}

bool clamshell_core_is_running(const ClamshellCore *core) { return core->nds->IsRunning(); }

uint32_t clamshell_core_run_frame(ClamshellCore *core) { return core->nds->RunFrame(); }

bool clamshell_core_copy_framebuffers(ClamshellCore *core, uint32_t *top, uint32_t *bottom)
{
    void *srcTop = nullptr;
    void *srcBottom = nullptr;
    if (!core->nds->GPU.GetFramebuffers(&srcTop, &srcBottom) || !srcTop || !srcBottom)
        return false;
    constexpr size_t bytes = CLAMSHELL_SCREEN_PIXELS * sizeof(uint32_t);
    std::memcpy(top, srcTop, bytes);
    std::memcpy(bottom, srcBottom, bytes);
    return true;
}

int32_t clamshell_core_read_audio(ClamshellCore *core, int16_t *buffer, int32_t frames)
{
    return core->nds->SPU.ReadOutput(buffer, frames);
}

int32_t clamshell_core_audio_frames_available(const ClamshellCore *core)
{
    return core->nds->SPU.GetOutputSize();
}

void clamshell_core_set_keys(ClamshellCore *core, uint32_t pressed)
{
    // melonDS expects KEYINPUT polarity: 0 = pressed. Bits 0-9 and 10-11 (X, Y).
    core->nds->SetKeyMask(~pressed & 0xFFFu);
}

void clamshell_core_touch(ClamshellCore *core, int32_t x, int32_t y)
{
    const auto cx = static_cast<u16>(std::clamp(x, 0, CLAMSHELL_SCREEN_WIDTH - 1));
    const auto cy = static_cast<u16>(std::clamp(y, 0, CLAMSHELL_SCREEN_HEIGHT - 1));
    core->nds->TouchScreen(cx, cy);
}

void clamshell_core_release_touch(ClamshellCore *core) { core->nds->ReleaseScreen(); }

void clamshell_core_set_lid_closed(ClamshellCore *core, bool closed)
{
    core->nds->SetLidClosed(closed);
}

bool clamshell_core_is_lid_closed(const ClamshellCore *core) { return core->nds->IsLidClosed(); }

uint8_t *clamshell_core_save_state(ClamshellCore *core, uint32_t *length)
{
    Savestate state;
    if (state.Error || !core->nds->DoSavestate(&state) || state.Error)
        return nullptr;
    state.Finish();

    const u32 size = state.Length();
    auto *out = static_cast<uint8_t *>(std::malloc(size));
    if (!out) return nullptr;
    std::memcpy(out, state.Buffer(), size);
    *length = size;
    return out;
}

bool clamshell_core_load_state(ClamshellCore *core, const uint8_t *data, uint32_t length)
{
    if (!data || length == 0) return false;

    // Keep a backup so a corrupt or incompatible state cannot leave the machine half-loaded.
    Savestate backup;
    if (backup.Error || !core->nds->DoSavestate(&backup) || backup.Error)
        return false;
    backup.Finish();

    // Savestate takes a mutable pointer but does not write when loading.
    Savestate state(const_cast<uint8_t *>(data), length, false);
    if (!state.Error && core->nds->DoSavestate(&state) && !state.Error)
        return true;

    Savestate restore(backup.Buffer(), backup.Length(), false);
    core->nds->DoSavestate(&restore);
    return false;
}

void clamshell_buffer_free(void *buffer) { std::free(buffer); }

const uint8_t *clamshell_core_save_memory(const ClamshellCore *core, uint32_t *length)
{
    const auto &slot = core->nds->NDSCartSlot;
    *length = slot.GetSaveMemoryLength();
    return *length ? slot.GetSaveMemory() : nullptr;
}

uint32_t clamshell_core_debug_read32(ClamshellCore *core, uint32_t address)
{
    return core->nds->ARM9Read32(address);
}

const int16_t *clamshell_mic_blow_samples(uint32_t *count)
{
    *count = sizeof(mic_blow) / sizeof(mic_blow[0]);
    return mic_blow;
}

const char *clamshell_core_melonds_version(void) { return MELONDS_VERSION; }

} // extern "C"
