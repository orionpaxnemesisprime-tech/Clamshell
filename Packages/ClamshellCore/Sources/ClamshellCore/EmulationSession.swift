// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization

/// Runs one game on a dedicated emulation thread at the handheld's frame rate.
///
/// Thread-safe: call from any thread (typically the main actor). The `EmulatorCore` lives
/// entirely on the emulation thread; this object only exchanges snapshots with it.
public final class EmulationSession: Sendable {
    public struct Statistics: Sendable, Equatable {
        public var framesRun: UInt64 = 0
        /// Emulated frames per second over roughly the last second.
        public var framesPerSecond: Double = 0
    }

    /// Frames for the renderer.
    public let frames = FrameStore()
    /// Audio for `AudioOutput` (interleaved stereo at `audioSampleRate`).
    public let audio: AudioRingBuffer
    public let audioSampleRate: Double

    private struct Control: Sendable {
        var keys: EmulatorKeys = []
        var touch: (x: Int, y: Int)?
        var lidClosed = false
        var paused = false
        var stopRequested = false
        var running = false
    }

    private let control = Mutex(Control())
    private let stats = Mutex(Statistics())
    private let wake = DispatchSemaphore(value: 0)
    /// Signalled by the current run's thread when it exits (one semaphore per run).
    private let runFinished = Mutex<DispatchSemaphore?>(nil)

    public init(audioSampleRate: Double = 48_000) {
        self.audioSampleRate = audioSampleRate
        audio = AudioRingBuffer()
    }

    deinit {
        stop()
    }

    // MARK: Lifecycle

    /// Called on the emulation thread with a copy of the whole battery save, at most once per
    /// `saveDebounce` while the game keeps writing, and again when pausing or stopping.
    public typealias SaveHandler = @Sendable (_ saveMemory: [UInt8]) -> Void

    /// Validates the ROM on the calling thread, then starts the emulation thread.
    public func start(rom: [UInt8], save: [UInt8]? = nil, name: String,
                      saveDebounce: Duration = .seconds(1),
                      onSave: SaveHandler? = nil) throws(EmulatorError) {
        stop()
        // Validate synchronously so callers get a load error immediately.
        try EmulatorCore(audioSampleRate: audioSampleRate).loadROM(rom, save: save, name: name)

        control.withLock { $0 = Control(running: true) }
        stats.withLock { $0 = Statistics() }
        audio.flush()

        let finished = DispatchSemaphore(value: 0)
        runFinished.withLock { $0 = finished }
        let thread = Thread { [self] in
            run(rom: rom, save: save, name: name, saveDebounce: saveDebounce, onSave: onSave)
            finished.signal()
        }
        thread.name = "Clamshell emulation"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops the emulation thread and waits for it to exit.
    public func stop() {
        control.withLock { $0.stopRequested = true }
        guard let finished = runFinished.withLock({ state in defer { state = nil }; return state })
        else { return }
        wake.signal()
        finished.wait()
    }

    public var isRunning: Bool { control.withLock { $0.running } }

    public var isPaused: Bool {
        get { control.withLock { $0.paused } }
        set {
            control.withLock { $0.paused = newValue }
            if !newValue { wake.signal() }
        }
    }

    public var statistics: Statistics { stats.withLock { $0 } }

    // MARK: Input (latest value wins; applied once per frame)

    public func setKeys(_ keys: EmulatorKeys) { control.withLock { $0.keys = keys } }
    public func touch(x: Int, y: Int) { control.withLock { $0.touch = (x, y) } }
    public func releaseTouch() { control.withLock { $0.touch = nil } }
    public func setLidClosed(_ closed: Bool) { control.withLock { $0.lidClosed = closed } }

    // MARK: Emulation thread

    private func run(rom: [UInt8], save: [UInt8]?, name: String,
                     saveDebounce: Duration, onSave: SaveHandler?) {
        defer { control.withLock { $0.running = false } }

        let core = EmulatorCore(audioSampleRate: audioSampleRate)
        let saves = SaveTracker()
        core.delegate = saves
        do { try core.loadROM(rom, save: save, name: name) } catch { return }
        core.start()

        // Hands the current save memory to `onSave` if the game wrote to it.
        func flushSave(force: Bool) {
            guard let onSave, let lastWrite = saves.lastWrite else { return }
            guard force || ContinuousClock.now - lastWrite >= saveDebounce else { return }
            saves.lastWrite = nil
            if let memory = core.saveMemory() { onSave(memory) }
        }
        defer { flushSave(force: true) }

        var pacer = FramePacer(frameRate: EmulatorCore.frameRate)
        var applied = Control()
        var wasTouching = false
        var audioScratch = [Int16](repeating: 0, count: 4_096)
        var windowStart = ContinuousClock.now
        var windowFrames = 0

        while true {
            let wanted = control.withLock { $0 }
            if wanted.stopRequested { break }

            if wanted.paused {
                flushSave(force: true) // pausing usually means the app is going to the background
                _ = wake.wait(timeout: .now() + .milliseconds(100))
                pacer.reset()
                continue
            }

            if wanted.keys != applied.keys { core.setKeys(wanted.keys) }
            if wanted.lidClosed != applied.lidClosed { core.isLidClosed = wanted.lidClosed }
            if let touch = wanted.touch {
                core.touch(x: touch.x, y: touch.y)
                wasTouching = true
            } else if wasTouching {
                core.releaseTouch()
                wasTouching = false
            }
            applied = wanted

            core.runFrame()
            if !core.isRunning { break } // the game powered the console off
            frames.publish { top, bottom in core.copyFrame(top: top, bottom: bottom) }
            flushSave(force: false)

            audioScratch.withUnsafeMutableBufferPointer { buffer in
                while true {
                    let read = core.readAudio(into: buffer)
                    if read == 0 { break }
                    audio.write(buffer.baseAddress!, frames: read)
                }
            }

            windowFrames += 1
            let now = ContinuousClock.now
            let elapsed = now - windowStart
            stats.withLock { stats in
                stats.framesRun += 1
                if elapsed >= .seconds(1) {
                    stats.framesPerSecond = Double(windowFrames) / (Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18)
                }
            }
            if elapsed >= .seconds(1) {
                windowStart = now
                windowFrames = 0
            }

            pacer.waitForNextFrame()
        }

        core.stop()
    }
}

/// Lives on the emulation thread; remembers when the game last wrote its battery save.
private final class SaveTracker: EmulatorCoreDelegate {
    var lastWrite: ContinuousClock.Instant?

    func emulatorCore(_ core: EmulatorCore, didWriteSave saveMemory: UnsafeRawBufferPointer, range: Range<Int>) {
        lastWrite = .now
    }
}
