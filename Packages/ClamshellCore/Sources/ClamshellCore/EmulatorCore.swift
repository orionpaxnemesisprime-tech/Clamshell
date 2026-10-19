// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellBridge

/// Buttons on the emulated handheld.
public struct EmulatorKeys: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let a = EmulatorKeys(rawValue: ClamshellKeyA.rawValue)
    public static let b = EmulatorKeys(rawValue: ClamshellKeyB.rawValue)
    public static let select = EmulatorKeys(rawValue: ClamshellKeySelect.rawValue)
    public static let start = EmulatorKeys(rawValue: ClamshellKeyStart.rawValue)
    public static let right = EmulatorKeys(rawValue: ClamshellKeyRight.rawValue)
    public static let left = EmulatorKeys(rawValue: ClamshellKeyLeft.rawValue)
    public static let up = EmulatorKeys(rawValue: ClamshellKeyUp.rawValue)
    public static let down = EmulatorKeys(rawValue: ClamshellKeyDown.rawValue)
    public static let r = EmulatorKeys(rawValue: ClamshellKeyR.rawValue)
    public static let l = EmulatorKeys(rawValue: ClamshellKeyL.rawValue)
    public static let x = EmulatorKeys(rawValue: ClamshellKeyX.rawValue)
    public static let y = EmulatorKeys(rawValue: ClamshellKeyY.rawValue)
}

public enum EmulatorError: Error, Equatable {
    case invalidROM
    case saveStateFailed
    case loadStateFailed
}

/// Two 256x192 screens of 32-bit BGRA pixels (alpha undefined; treat as opaque).
public struct ScreenFrame: Sendable, Equatable {
    public static let width = Int(CLAMSHELL_SCREEN_WIDTH)
    public static let height = Int(CLAMSHELL_SCREEN_HEIGHT)
    public static let pixelCount = Int(CLAMSHELL_SCREEN_PIXELS)

    public var top: [UInt32]
    public var bottom: [UInt32]

    public init() {
        top = Array(repeating: 0, count: Self.pixelCount)
        bottom = Array(repeating: 0, count: Self.pixelCount)
    }
}

/// Receives events from the core. Called on the emulation thread.
public protocol EmulatorCoreDelegate: AnyObject {
    /// Battery-save memory changed. `saveMemory` is the whole buffer, valid only during the call.
    func emulatorCore(_ core: EmulatorCore, didWriteSave saveMemory: UnsafeRawBufferPointer,
                      range: Range<Int>)
    /// The emulated console stopped itself.
    func emulatorCoreDidRequestStop(_ core: EmulatorCore)
    /// The game opened the microphone. Request permission / start capture here.
    func emulatorCoreDidStartMicrophone(_ core: EmulatorCore)
    func emulatorCoreDidStopMicrophone(_ core: EmulatorCore)
    /// Fill `buffer` with signed 16-bit mono samples at ~47.6 kHz; return the count written.
    /// Must not block.
    func emulatorCore(_ core: EmulatorCore, readMicrophoneInto buffer: UnsafeMutableBufferPointer<Int16>) -> Int
}

public extension EmulatorCoreDelegate {
    func emulatorCore(_ core: EmulatorCore, didWriteSave saveMemory: UnsafeRawBufferPointer,
                      range: Range<Int>) {}
    func emulatorCoreDidRequestStop(_ core: EmulatorCore) {}
    func emulatorCoreDidStartMicrophone(_ core: EmulatorCore) {}
    func emulatorCoreDidStopMicrophone(_ core: EmulatorCore) {}
    func emulatorCore(_ core: EmulatorCore, readMicrophoneInto buffer: UnsafeMutableBufferPointer<Int16>) -> Int { 0 }
}

/// One emulated machine (melonDS, interpreter only).
///
/// Not thread-safe and deliberately not `Sendable`: create it and call every method on the
/// single emulation thread that owns it.
public final class EmulatorCore {
    /// Emulated refresh rate in Hz.
    public static let frameRate = CLAMSHELL_FRAME_RATE
    public static var melonDSVersion: String { String(cString: clamshell_core_melonds_version()) }

    public weak var delegate: EmulatorCoreDelegate?

    private var handle: OpaquePointer!

    public init(audioSampleRate: Double = 48_000) {
        var callbacks = ClamshellCoreCallbacks()
        callbacks.context = nil
        callbacks.saveWritten = { context, data, length, offset, writeLength in
            guard let context, let data else { return }
            let core = Unmanaged<EmulatorCore>.fromOpaque(context).takeUnretainedValue()
            let buffer = UnsafeRawBufferPointer(start: data, count: Int(length))
            let lower = Int(offset)
            let upper = min(lower + Int(writeLength), Int(length))
            core.delegate?.emulatorCore(core, didWriteSave: buffer, range: lower..<upper)
        }
        callbacks.stopRequested = { context, _ in
            guard let context else { return }
            let core = Unmanaged<EmulatorCore>.fromOpaque(context).takeUnretainedValue()
            core.delegate?.emulatorCoreDidRequestStop(core)
        }
        callbacks.micStart = { context in
            guard let context else { return }
            let core = Unmanaged<EmulatorCore>.fromOpaque(context).takeUnretainedValue()
            core.delegate?.emulatorCoreDidStartMicrophone(core)
        }
        callbacks.micStop = { context in
            guard let context else { return }
            let core = Unmanaged<EmulatorCore>.fromOpaque(context).takeUnretainedValue()
            core.delegate?.emulatorCoreDidStopMicrophone(core)
        }
        callbacks.micRead = { context, samples, maxSamples in
            guard let context, let samples, maxSamples > 0 else { return 0 }
            let core = Unmanaged<EmulatorCore>.fromOpaque(context).takeUnretainedValue()
            let buffer = UnsafeMutableBufferPointer(start: samples, count: Int(maxSamples))
            let written = core.delegate?.emulatorCore(core, readMicrophoneInto: buffer) ?? 0
            return Int32(clamping: min(max(written, 0), Int(maxSamples)))
        }
        handle = clamshell_core_create(callbacks, audioSampleRate)
        // The core holds an unretained back-pointer; it never outlives `self` (see deinit).
        clamshell_core_set_context(handle, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        clamshell_core_destroy(handle)
    }

    /// Inserts a cartridge image, resets and direct-boots it. Call `start()` afterwards.
    public func loadROM(_ rom: [UInt8], save: [UInt8]? = nil, name: String = "game.nds") throws(EmulatorError) {
        let result = rom.withUnsafeBufferPointer { romBuffer in
            withOptionalBuffer(save) { saveBuffer in
                clamshell_core_load_rom(handle, romBuffer.baseAddress, UInt32(romBuffer.count),
                                        saveBuffer?.baseAddress, UInt32(saveBuffer?.count ?? 0), name)
            }
        }
        guard result == ClamshellLoadResultOK else { throw .invalidROM }
    }

    public func start() { clamshell_core_start(handle) }
    public func stop() { clamshell_core_stop(handle) }
    public func reset() { clamshell_core_reset(handle) }
    public var isRunning: Bool { clamshell_core_is_running(handle) }

    /// Runs one emulated frame. Returns false if no frame was produced.
    @discardableResult
    public func runFrame() -> Bool { clamshell_core_run_frame(handle) > 0 }

    /// Copies the latest frame into `frame`, reusing its storage.
    @discardableResult
    public func copyFrame(into frame: inout ScreenFrame) -> Bool {
        frame.top.withUnsafeMutableBufferPointer { top in
            frame.bottom.withUnsafeMutableBufferPointer { bottom in
                clamshell_core_copy_framebuffers(handle, top.baseAddress, bottom.baseAddress)
            }
        }
    }

    /// Reads up to `buffer.count / 2` interleaved stereo frames. Returns frames read.
    public func readAudio(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        Int(clamshell_core_read_audio(handle, buffer.baseAddress, Int32(buffer.count / 2)))
    }

    public var audioFramesAvailable: Int { Int(clamshell_core_audio_frames_available(handle)) }

    public func setKeys(_ pressed: EmulatorKeys) { clamshell_core_set_keys(handle, pressed.rawValue) }

    /// Touch-screen coordinates; clamped to 0...255, 0...191.
    public func touch(x: Int, y: Int) {
        clamshell_core_touch(handle, Int32(clamping: x), Int32(clamping: y))
    }

    public func releaseTouch() { clamshell_core_release_touch(handle) }

    public var isLidClosed: Bool {
        get { clamshell_core_is_lid_closed(handle) }
        set { clamshell_core_set_lid_closed(handle, newValue) }
    }

    public func saveState() throws(EmulatorError) -> [UInt8] {
        var length: UInt32 = 0
        guard let buffer = clamshell_core_save_state(handle, &length) else { throw .saveStateFailed }
        defer { clamshell_buffer_free(buffer) }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(length)))
    }

    /// Restores a state. On failure the machine is left exactly as it was.
    public func loadState(_ state: [UInt8]) throws(EmulatorError) {
        let ok = state.withUnsafeBufferPointer {
            clamshell_core_load_state(handle, $0.baseAddress, UInt32($0.count))
        }
        guard ok else { throw .loadStateFailed }
    }

    /// Current battery-save memory, or nil if the cartridge has none.
    public func saveMemory() -> [UInt8]? {
        var length: UInt32 = 0
        guard let pointer = clamshell_core_save_memory(handle, &length) else { return nil }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(length)))
    }

    /// Reads a word from the ARM9 bus. For tests and debugging only.
    public func debugRead32(_ address: UInt32) -> UInt32 {
        clamshell_core_debug_read32(handle, address)
    }
}

private func withOptionalBuffer<R>(_ array: [UInt8]?, _ body: (UnsafeBufferPointer<UInt8>?) -> R) -> R {
    guard let array else { return body(nil) }
    return array.withUnsafeBufferPointer { body($0) }
}
