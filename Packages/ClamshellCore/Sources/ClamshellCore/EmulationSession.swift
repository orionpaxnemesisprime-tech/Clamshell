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

    /// Work that must run on the emulation thread between frames.
    private enum Command: Sendable {
        case saveState(CheckedContinuation<[UInt8], any Error>)
        case loadState([UInt8], CheckedContinuation<Void, any Error>)

        func fail(_ error: EmulatorError) {
            switch self {
            case .saveState(let continuation): continuation.resume(throwing: error)
            case .loadState(_, let continuation): continuation.resume(throwing: error)
            }
        }
    }

    private struct Control: Sendable {
        var commands: [Command] = []
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

    /// Where microphone samples come from when a game opens the mic (nil: silence).
    public let microphone: (any MicrophoneSource)?

    public init(audioSampleRate: Double = 48_000, microphone: (any MicrophoneSource)? = nil) {
        self.audioSampleRate = audioSampleRate
        self.microphone = microphone
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
    public func start(rom: [UInt8], save: [UInt8]? = nil, name: String, sdCard: URL? = nil,
                      saveDebounce: Duration = .seconds(1),
                      onSave: SaveHandler? = nil) throws(EmulatorError) {
        stop()
        // Validate synchronously so callers get a load error immediately (no SD card needed).
        try EmulatorCore(audioSampleRate: audioSampleRate).loadROM(rom, save: save, name: name)

        control.withLock { $0 = Control(running: true) }
        stats.withLock { $0 = Statistics() }
        audio.flush()

        let finished = DispatchSemaphore(value: 0)
        runFinished.withLock { $0 = finished }
        let thread = Thread { [self] in
            run(rom: rom, save: save, name: name, sdCard: sdCard, saveDebounce: saveDebounce, onSave: onSave)
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

    // MARK: Save states (run on the emulation thread between frames, also while paused)

    /// Captures the whole machine state.
    public func saveState() async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(.saveState(continuation))
        }
    }

    /// Restores a state from `saveState()`. On failure the machine is left untouched.
    public func loadState(_ state: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            enqueue(.loadState(state, continuation))
        }
    }

    private func enqueue(_ command: Command) {
        let accepted = control.withLock { control in
            guard control.running, !control.stopRequested else { return false }
            control.commands.append(command)
            return true
        }
        guard accepted else { return command.fail(.notRunning) }
        wake.signal()
    }

    // MARK: Emulation thread

    private func run(rom: [UInt8], save: [UInt8]?, name: String, sdCard: URL?,
                     saveDebounce: Duration, onSave: SaveHandler?) {
        defer {
            // Fail anything still queued so no caller waits forever.
            let leftover = control.withLock { control in
                control.running = false
                defer { control.commands = [] }
                return control.commands
            }
            leftover.forEach { $0.fail(.notRunning) }
        }

        let core = EmulatorCore(audioSampleRate: audioSampleRate)
        let saves = CoreEvents(microphone: microphone)
        core.delegate = saves
        defer { if saves.microphoneOpen { microphone?.stop() } }
        do { try core.loadROM(rom, save: save, name: name, sdCard: sdCard) } catch { return }
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
            let wanted = control.withLock { control in
                defer { control.commands = [] }
                return control
            }
            if wanted.stopRequested {
                wanted.commands.forEach { $0.fail(.notRunning) }
                break
            }

            for command in wanted.commands {
                switch command {
                case .saveState(let continuation):
                    do { continuation.resume(returning: try core.saveState()) }
                    catch { continuation.resume(throwing: error) }
                case .loadState(let state, let continuation):
                    do {
                        try core.loadState(state)
                        frames.publish { top, bottom in core.copyFrame(top: top, bottom: bottom) }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

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

/// Lives on the emulation thread: remembers battery-save writes and forwards the microphone.
private final class CoreEvents: EmulatorCoreDelegate {
    var lastWrite: ContinuousClock.Instant?
    private(set) var microphoneOpen = false
    private let microphone: (any MicrophoneSource)?

    init(microphone: (any MicrophoneSource)?) {
        self.microphone = microphone
    }

    func emulatorCore(_ core: EmulatorCore, didWriteSave saveMemory: UnsafeRawBufferPointer, range: Range<Int>) {
        lastWrite = .now
    }

    func emulatorCoreDidStartMicrophone(_ core: EmulatorCore) {
        guard !microphoneOpen else { return }
        microphoneOpen = true
        microphone?.start()
    }

    func emulatorCoreDidStopMicrophone(_ core: EmulatorCore) {
        guard microphoneOpen else { return }
        microphoneOpen = false
        microphone?.stop()
    }

    func emulatorCore(_ core: EmulatorCore, readMicrophoneInto buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        microphone?.read(into: buffer) ?? 0
    }
}
