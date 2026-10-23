// Clamshell — implementation of melonDS's Platform interface for iOS/macOS.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// File-mode handling follows melonDS's Qt frontend
// (src/frontend/qt_sdl/Platform.cpp, GPLv3, (c) melonDS team).

#include "BridgeInternal.h"
#include "Platform.h"
#include "SPI_Firmware.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>

#include <sys/stat.h>
#include <unistd.h>

namespace {

std::mutex logMutex;
void (*logHandler)(void *, ClamshellLogLevel, const char *) = nullptr;
void *logContext = nullptr;

ClamshellCoreCallbacks *callbacksFor(void *userdata, void **context)
{
    ClamshellCoreCallbacks *callbacks = nullptr;
    *context = clamshell_internal_callbacks_context(userdata, &callbacks);
    return callbacks;
}

} // namespace

extern "C" void clamshell_set_log_handler(void (*handler)(void *, ClamshellLogLevel, const char *),
                                          void *context)
{
    std::lock_guard lock(logMutex);
    logHandler = handler;
    logContext = context;
}

namespace melonDS::Platform {

// MARK: Lifecycle

void SignalStop(StopReason reason, void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->stopRequested)
        cb->stopRequested(context, static_cast<int32_t>(reason));
}

// MARK: Files
// The core only touches files for optional features (homebrew SD images). Paths are
// supplied by Clamshell and always point inside the app container.

static constexpr char AccessMode(FileMode mode, bool fileExists)
{
    if (mode & FileMode::Append) return 'a';
    if (!(mode & FileMode::Write)) return 'r';
    if (mode & FileMode::NoCreate) return 'r';
    if ((mode & FileMode::Preserve) && fileExists) return 'r';
    return 'w';
}

static constexpr bool IsExtended(FileMode mode)
{
    return (mode & FileMode::ReadWrite) == FileMode::ReadWrite;
}

FileHandle *OpenFile(const std::string &path, FileMode mode)
{
    if ((mode & (FileMode::ReadWrite | FileMode::Append)) == FileMode::None)
        return nullptr;

    const bool exists = FileExists(path);
    if ((mode & FileMode::NoCreate) && !exists)
        return nullptr;

    std::string modeString(1, AccessMode(mode, exists));
    if (IsExtended(mode)) modeString += '+';
    if (!(mode & FileMode::Text)) modeString += 'b';

    return reinterpret_cast<FileHandle *>(std::fopen(path.c_str(), modeString.c_str()));
}

std::string GetLocalFilePath(const std::string &filename) { return filename; }

FileHandle *OpenLocalFile(const std::string &path, FileMode mode)
{
    return OpenFile(GetLocalFilePath(path), mode);
}

bool FileExists(const std::string &name)
{
    struct stat info;
    return stat(name.c_str(), &info) == 0 && S_ISREG(info.st_mode);
}

bool LocalFileExists(const std::string &name) { return FileExists(GetLocalFilePath(name)); }

bool CheckFileWritable(const std::string &filepath)
{
    if (FileExists(filepath))
        return access(filepath.c_str(), W_OK) == 0;
    FileHandle *file = OpenFile(filepath, FileMode::Write);
    if (!file) return false;
    CloseFile(file);
    std::remove(filepath.c_str());
    return true;
}

bool CheckLocalFileWritable(const std::string &filepath)
{
    return CheckFileWritable(GetLocalFilePath(filepath));
}

static FILE *AsFILE(FileHandle *file) { return reinterpret_cast<FILE *>(file); }

bool CloseFile(FileHandle *file) { return std::fclose(AsFILE(file)) == 0; }
bool IsEndOfFile(FileHandle *file) { return std::feof(AsFILE(file)) != 0; }

bool FileReadLine(char *str, int count, FileHandle *file)
{
    return std::fgets(str, count, AsFILE(file)) != nullptr;
}

u64 FilePosition(FileHandle *file) { return static_cast<u64>(ftello(AsFILE(file))); }

bool FileSeek(FileHandle *file, s64 offset, FileSeekOrigin origin)
{
    int whence = SEEK_SET;
    if (origin == FileSeekOrigin::Current) whence = SEEK_CUR;
    else if (origin == FileSeekOrigin::End) whence = SEEK_END;
    return fseeko(AsFILE(file), offset, whence) == 0;
}

void FileRewind(FileHandle *file) { std::rewind(AsFILE(file)); }

u64 FileRead(void *data, u64 size, u64 count, FileHandle *file)
{
    return std::fread(data, size, count, AsFILE(file));
}

bool FileFlush(FileHandle *file) { return std::fflush(AsFILE(file)) == 0; }

u64 FileWrite(const void *data, u64 size, u64 count, FileHandle *file)
{
    return std::fwrite(data, size, count, AsFILE(file));
}

u64 FileWriteFormatted(FileHandle *file, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    const int written = std::vfprintf(AsFILE(file), fmt, args);
    va_end(args);
    return written < 0 ? 0 : static_cast<u64>(written);
}

u64 FileLength(FileHandle *file)
{
    FILE *f = AsFILE(file);
    const off_t position = ftello(f);
    fseeko(f, 0, SEEK_END);
    const off_t length = ftello(f);
    fseeko(f, position, SEEK_SET);
    return static_cast<u64>(length);
}

// MARK: Logging

void Log(LogLevel level, const char *fmt, ...)
{
    char message[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(message, sizeof(message), fmt, args);
    va_end(args);

    std::lock_guard lock(logMutex);
    if (logHandler)
        logHandler(logContext, static_cast<ClamshellLogLevel>(level), message);
}

// MARK: Threads and synchronisation

struct Thread {
    std::thread thread;
};

Thread *Thread_Create(std::function<void()> func) { return new Thread { std::thread(std::move(func)) }; }

void Thread_Wait(Thread *thread)
{
    if (thread->thread.joinable()) thread->thread.join();
}

void Thread_Free(Thread *thread)
{
    Thread_Wait(thread);
    delete thread;
}

struct Semaphore {
    std::mutex mutex;
    std::condition_variable condition;
    int count = 0;
};

Semaphore *Semaphore_Create() { return new Semaphore; }
void Semaphore_Free(Semaphore *sema) { delete sema; }

void Semaphore_Reset(Semaphore *sema)
{
    std::lock_guard lock(sema->mutex);
    sema->count = 0;
}

void Semaphore_Wait(Semaphore *sema)
{
    std::unique_lock lock(sema->mutex);
    sema->condition.wait(lock, [sema] { return sema->count > 0; });
    --sema->count;
}

bool Semaphore_TryWait(Semaphore *sema, int timeout_ms)
{
    std::unique_lock lock(sema->mutex);
    const auto ready = [sema] { return sema->count > 0; };
    if (timeout_ms <= 0 ? !ready()
                        : !sema->condition.wait_for(lock, std::chrono::milliseconds(timeout_ms), ready))
        return false;
    --sema->count;
    return true;
}

void Semaphore_Post(Semaphore *sema, int count)
{
    {
        std::lock_guard lock(sema->mutex);
        sema->count += count;
    }
    sema->condition.notify_all();
}

struct Mutex {
    std::mutex mutex;
};

Mutex *Mutex_Create() { return new Mutex; }
void Mutex_Free(Mutex *mutex) { delete mutex; }
void Mutex_Lock(Mutex *mutex) { mutex->mutex.lock(); }
void Mutex_Unlock(Mutex *mutex) { mutex->mutex.unlock(); }
bool Mutex_TryLock(Mutex *mutex) { return mutex->mutex.try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }

u64 GetMSCount()
{
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

u64 GetUSCount()
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

// MARK: Persistence

void WriteNDSSave(const u8 *savedata, u32 savelen, u32 writeoffset, u32 writelen, void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->saveWritten)
        cb->saveWritten(context, savedata, savelen, writeoffset, writelen);
}

// GBA slot and firmware persistence are not supported yet; generated firmware is rebuilt
// on every launch.
void WriteGBASave(const u8 *, u32, u32, u32, void *) {}
void WriteFirmware(const Firmware &, u32, u32, void *) {}
void WriteDateTime(int, int, int, int, int, int, void *) {}

// MARK: Local multiplayer and Wi-Fi (not supported)

void MP_Begin(void *) {}
void MP_End(void *) {}
int MP_SendPacket(u8 *, int, u64, void *) { return 0; }
int MP_RecvPacket(u8 *, u64 *, void *) { return 0; }
int MP_SendCmd(u8 *, int, u64, void *) { return 0; }
int MP_SendReply(u8 *, int, u64, u16, void *) { return 0; }
int MP_SendAck(u8 *, int, u64, void *) { return 0; }
int MP_RecvHostPacket(u8 *, u64 *, void *) { return 0; }
u16 MP_RecvReplies(u8 *, u64, u16, void *) { return 0; }
int Net_SendPacket(u8 *, int, void *) { return 0; }
int Net_RecvPacket(u8 *, void *) { return 0; }

// MARK: Camera and AAC (DSi only, not supported)

void Camera_Start(int, void *) {}
void Camera_Stop(int, void *) {}
void Camera_CaptureFrame(int, u32 *, int, int, bool, void *) {}

AACDecoder *AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder *) {}
bool AAC_Configure(AACDecoder *, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder *, const void *, int, void *, int) { return false; }

// MARK: Microphone

void Mic_Start(void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->micStart)
        cb->micStart(context);
}

void Mic_Stop(void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->micStop)
        cb->micStop(context);
}

int Mic_ReadInput(s16 *data, int maxlength, void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->micRead)
        return cb->micRead(context, data, maxlength);
    return 0;
}

// MARK: Slot-2 add-ons (Rumble Pak only)

bool Addon_KeyDown(KeyType, void *) { return false; }

void Addon_RumbleStart(u32 len, void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->rumbleStart)
        cb->rumbleStart(context, len);
}

void Addon_RumbleStop(void *userdata)
{
    void *context;
    if (auto *cb = callbacksFor(userdata, &context); cb && cb->rumbleStop)
        cb->rumbleStop(context);
}

float Addon_MotionQuery(MotionQueryType, void *) { return 0.0f; }

// MARK: Dynamic libraries
// iOS apps cannot load code at runtime (App Review 2.5.2), so this is always unavailable.

DynamicLibrary *DynamicLibrary_Load(const char *) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary *) {}
void *DynamicLibrary_LoadFunction(DynamicLibrary *, const char *) { return nullptr; }

} // namespace melonDS::Platform
