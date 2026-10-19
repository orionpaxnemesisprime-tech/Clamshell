// Clamshell — C facade over the melonDS core.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This is the only header Swift sees. It deliberately exposes plain C types so that
// Swift needs no C++ interop. All functions taking a ClamshellCore must be called from
// the single emulation thread that owns it, unless documented otherwise.

#ifndef CLAMSHELL_BRIDGE_H
#define CLAMSHELL_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CLAMSHELL_SCREEN_WIDTH 256
#define CLAMSHELL_SCREEN_HEIGHT 192
#define CLAMSHELL_SCREEN_PIXELS (CLAMSHELL_SCREEN_WIDTH * CLAMSHELL_SCREEN_HEIGHT)

/// Emulated frame rate of the handheld (Hz).
#define CLAMSHELL_FRAME_RATE 59.8260982880808

typedef struct ClamshellCore ClamshellCore;

typedef enum ClamshellLogLevel {
    ClamshellLogLevelDebug = 0,
    ClamshellLogLevelInfo = 1,
    ClamshellLogLevelWarn = 2,
    ClamshellLogLevelError = 3,
} ClamshellLogLevel;

/// Pressed-button bits. The bridge converts these to the hardware's active-low KEYINPUT layout.
typedef enum ClamshellKey : uint32_t {
    ClamshellKeyA      = 1u << 0,
    ClamshellKeyB      = 1u << 1,
    ClamshellKeySelect = 1u << 2,
    ClamshellKeyStart  = 1u << 3,
    ClamshellKeyRight  = 1u << 4,
    ClamshellKeyLeft   = 1u << 5,
    ClamshellKeyUp     = 1u << 6,
    ClamshellKeyDown   = 1u << 7,
    ClamshellKeyR      = 1u << 8,
    ClamshellKeyL      = 1u << 9,
    ClamshellKeyX      = 1u << 10,
    ClamshellKeyY      = 1u << 11,
} ClamshellKey;

typedef enum ClamshellLoadResult {
    ClamshellLoadResultOK = 0,
    ClamshellLoadResultInvalidROM = 1,
} ClamshellLoadResult;

/// Callbacks from the core. Every pointer may be NULL. They are invoked on the emulation
/// thread, except `log`, which can also be called from melonDS worker threads.
typedef struct ClamshellCoreCallbacks {
    void *context;
    /// Battery-save write. `data`/`length` is the whole save memory; the changed range is
    /// [offset, offset + writeLength). Copy what you need before returning.
    void (*saveWritten)(void *context, const uint8_t *data, uint32_t length,
                        uint32_t offset, uint32_t writeLength);
    /// The core stopped itself (for example, the game powered the console off).
    void (*stopRequested)(void *context, int32_t reason);
    void (*micStart)(void *context);
    void (*micStop)(void *context);
    /// Fill up to `maxSamples` signed 16-bit mono samples at ~47.6 kHz. Return the number
    /// written. Must not block.
    int32_t (*micRead)(void *context, int16_t *samples, int32_t maxSamples);
    /// Rumble Pak motor pulse of `milliseconds`, and its end.
    void (*rumbleStart)(void *context, uint32_t milliseconds);
    void (*rumbleStop)(void *context);
} ClamshellCoreCallbacks;

/// Process-wide log sink (melonDS logging has no per-instance context). Thread-safe.
void clamshell_set_log_handler(void (*handler)(void *context, ClamshellLogLevel level,
                                               const char *message),
                               void *context);

/// Creates a core with FreeBIOS, generated firmware, the software renderer and the JIT
/// disabled. `audioSampleRate` is the output rate for clamshell_core_read_audio.
ClamshellCore *clamshell_core_create(ClamshellCoreCallbacks callbacks, double audioSampleRate);
void clamshell_core_destroy(ClamshellCore *core);
/// Replaces `callbacks.context` (for wrappers that only know their own address after creation).
void clamshell_core_set_context(ClamshellCore *core, void *context);

/// Inserts a cartridge image (copied) with optional existing save memory (copied), resets
/// and direct-boots it. Call clamshell_core_start afterwards.
///
/// `sdCardPath` (may be NULL) is a FAT disk image exposed to homebrew through DLDI; melonDS
/// creates and formats it on first use. `sdCardSize` is its size in bytes (0: auto). Ignored
/// for retail cartridges.
ClamshellLoadResult clamshell_core_load_rom(ClamshellCore *core,
                                            const uint8_t *rom, uint32_t romLength,
                                            const uint8_t *save, uint32_t saveLength,
                                            const char *romName,
                                            const char *sdCardPath, uint64_t sdCardSize);
/// Inserts (or not) a Rumble Pak in the Slot-2 port at the next clamshell_core_load_rom.
void clamshell_core_set_rumble_pak(ClamshellCore *core, bool inserted);

void clamshell_core_start(ClamshellCore *core);
void clamshell_core_stop(ClamshellCore *core);
void clamshell_core_reset(ClamshellCore *core);
bool clamshell_core_is_running(const ClamshellCore *core);

/// Runs one emulated frame. Returns the number of scanlines run (0: no frame produced).
uint32_t clamshell_core_run_frame(ClamshellCore *core);

/// Copies the latest frame into two buffers of CLAMSHELL_SCREEN_PIXELS 32-bit BGRA pixels
/// (top, bottom). Alpha is undefined; treat pixels as opaque. Returns false if unavailable.
bool clamshell_core_copy_framebuffers(ClamshellCore *core, uint32_t *top, uint32_t *bottom);

/// Reads up to `frames` interleaved stereo s16 frames. Returns frames read.
int32_t clamshell_core_read_audio(ClamshellCore *core, int16_t *buffer, int32_t frames);
int32_t clamshell_core_audio_frames_available(const ClamshellCore *core);

/// `pressed` is a bitwise OR of ClamshellKey values.
void clamshell_core_set_keys(ClamshellCore *core, uint32_t pressed);
/// Coordinates are clamped to the 256x192 touch screen.
void clamshell_core_touch(ClamshellCore *core, int32_t x, int32_t y);
void clamshell_core_release_touch(ClamshellCore *core);
void clamshell_core_set_lid_closed(ClamshellCore *core, bool closed);
bool clamshell_core_is_lid_closed(const ClamshellCore *core);

/// Serialises the machine. On success returns a malloc'd buffer the caller frees with
/// clamshell_buffer_free, and writes its length to `length`. Returns NULL on failure.
uint8_t *clamshell_core_save_state(ClamshellCore *core, uint32_t *length);
bool clamshell_core_load_state(ClamshellCore *core, const uint8_t *data, uint32_t length);
void clamshell_buffer_free(void *buffer);

/// Current battery-save memory (NULL if the cart has none). Valid until the next core call.
const uint8_t *clamshell_core_save_memory(const ClamshellCore *core, uint32_t *length);

/// Test/debug hook: reads a 32-bit word from the ARM9 bus.
uint32_t clamshell_core_debug_read32(ClamshellCore *core, uint32_t address);

/// A recorded "blow into the microphone" sound (s16 mono, ~47.6 kHz) for games that expect
/// blowing when no microphone is available. From melonDS (GPLv3).
const int16_t *clamshell_mic_blow_samples(uint32_t *count);

/// The melonDS revision this bridge was built against.
const char *clamshell_core_melonds_version(void);

#ifdef __cplusplus
}
#endif

#endif // CLAMSHELL_BRIDGE_H
