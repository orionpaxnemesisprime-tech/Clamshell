// SPDX-License-Identifier: GPL-3.0-or-later

@testable import ClamshellCore
import Foundation
import CoreGraphics
import ImageIO
import Synchronization
import Testing

private func romBytes(_ name: String) throws -> [UInt8] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "nds", subdirectory: "ROMs"))
    return Array(try Data(contentsOf: url))
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct SessionSaveStateTests {
    @Test func saveAndLoadStateRoundTripThroughTheThread() async throws {
        let session = EmulationSession()
        try session.start(rom: romBytes("smoketest"), name: "smoketest.nds")
        defer { session.stop() }
        try await Task.sleep(for: .milliseconds(300))

        let state = try await session.saveState()
        #expect(!state.isEmpty)
        let framesAtSave = session.statistics.framesRun
        try await Task.sleep(for: .milliseconds(300))
        try await session.loadState(state)
        #expect(session.statistics.framesRun > framesAtSave, "the session keeps running after loading")
    }

    @Test func worksWhilePausedAndRejectsGarbage() async throws {
        let session = EmulationSession()
        try session.start(rom: romBytes("smoketest"), name: "smoketest.nds")
        defer { session.stop() }
        try await Task.sleep(for: .milliseconds(200))
        session.isPaused = true

        let state = try await session.saveState()
        try await session.loadState(state)
        await #expect(throws: EmulatorError.loadStateFailed) {
            try await session.loadState([1, 2, 3, 4])
        }
    }

    @Test func failsWhenNotRunning() async {
        let session = EmulationSession()
        await #expect(throws: EmulatorError.notRunning) { try await session.saveState() }
    }
}

@Suite struct StateStoreTests {
    private func temporaryStore() -> StateStore {
        StateStore(directory: FileManager.default.temporaryDirectory.appending(path: "clamshell-states-\(UUID())"))
    }

    @Test func slotsRoundTripWithThumbnails() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let id = String(repeating: "ab", count: 20)

        let initiallyEmpty = store.slots(romID: id, count: 4).allSatisfy { $0.isEmpty }
        #expect(initiallyEmpty)
        #expect(throws: StateStore.StateError.empty) { try store.read(romID: id, slot: 1) }

        var frame = ScreenFrame()
        frame.top = Array(repeating: 0x00FF_0000, count: ScreenFrame.pixelCount)
        let png = try #require(frame.pngData())
        try store.write([9, 8, 7], thumbnail: png, romID: id, slot: 1)

        let slots = store.slots(romID: id, count: 4)
        #expect(!slots[1].isEmpty && slots[1].thumbnailURL != nil)
        #expect(slots[0].isEmpty && slots[2].isEmpty)
        let restored = try store.read(romID: id, slot: 1)
        #expect(restored == [9, 8, 7])

        store.delete(romID: id, slot: 1)
        #expect(store.slots(romID: id, count: 4)[1].isEmpty)
    }

    @Test func refusesStatesFromAnotherGameOrCorruptFiles() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let mine = String(repeating: "aa", count: 20)
        let other = String(repeating: "bb", count: 20)
        try store.write([1], thumbnail: nil, romID: mine, slot: 0)

        // Copy the file into another game's folder: the embedded ROM id must not match.
        try FileManager.default.createDirectory(at: store.stateURL(romID: other, slot: 0).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.stateURL(romID: mine, slot: 0), to: store.stateURL(romID: other, slot: 0))
        #expect(throws: StateStore.StateError.differentGame) { try store.read(romID: other, slot: 0) }

        try Data([0, 1, 2]).write(to: store.stateURL(romID: mine, slot: 2))
        #expect(throws: StateStore.StateError.corrupt) { try store.read(romID: mine, slot: 2) }
    }

    @Test func realStatesAreCompressedOnDisk() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = EmulationSession()
        try session.start(rom: romBytes("smoketest"), name: "smoketest.nds")
        defer { session.stop() }
        try await Task.sleep(for: .milliseconds(200))
        let state = try await session.saveState()

        let id = String(repeating: "cd", count: 20)
        try store.write(state, thumbnail: nil, romID: id, slot: 0)
        let onDisk = try Data(contentsOf: store.stateURL(romID: id, slot: 0)).count
        #expect(onDisk * 10 < state.count, "\(state.count) bytes stored as \(onDisk)")
        let restored = try store.read(romID: id, slot: 0)
        #expect(restored == state)
    }

    @Test func thumbnailIsAStackedOpaqueImage() throws {
        var frame = ScreenFrame()
        frame.bottom = Array(repeating: 0x0000_00FF, count: ScreenFrame.pixelCount) // blue, alpha 0
        let png = try #require(frame.pngData())
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 256 && image.height == 384)
    }
}

@Suite struct HingeLidTrackerTests {
    @Test func closesAndOpensWithHysteresis() {
        var lid = HingeLidTracker()
        let states = [180.0, 15, 5, 20, 40].map { lid.update(angleDegrees: $0) }
        // Half-closed (15°) is still open; once closed it stays closed inside the band (20°).
        #expect(states == [false, false, true, true, false])
    }
}

/// A fake microphone that records lifecycle calls and plays a constant level.
final class FakeMicrophone: MicrophoneSource {
    let events = Mutex<[String]>([])
    let level: Int16
    init(level: Int16) { self.level = level }
    func start() { events.withLock { $0.append("start") } }
    func stop() { events.withLock { $0.append("stop") } }
    func read(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        buffer.update(repeating: level)
        return buffer.count
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct MicrophoneTests {
    @Test func ringRoundTripsAndBoundsCapacity() {
        let ring = MonoSampleRing(capacity: 4)
        let samples: [Int16] = [1, 2, 3, 4, 5, 6]
        #expect(samples.withUnsafeBufferPointer { ring.write($0) } == 4)
        var out = [Int16](repeating: 0, count: 3)
        #expect(out.withUnsafeMutableBufferPointer { ring.read(into: $0) } == 3)
        #expect(out == [1, 2, 3])
        #expect([Int16](arrayLiteral: 7, 8).withUnsafeBufferPointer { ring.write($0) } == 2) // wraps
        var rest = [Int16](repeating: 0, count: 8)
        #expect(rest.withUnsafeMutableBufferPointer { ring.read(into: $0) } == 3)
        #expect(Array(rest.prefix(3)) == [4, 7, 8])
    }

    @Test func sessionOpensTheMicOnlyWhenTheGameSamplesIt() async throws {
        let mic = FakeMicrophone(level: 16_000)
        let session = EmulationSession(microphone: mic)
        let router = InputRouter(session: session)
        try session.start(rom: romBytes("iotest"), name: "iotest.nds")
        try await Task.sleep(for: .milliseconds(300))
        #expect(mic.events.withLock { $0.isEmpty }, "no mic until the game asks")

        router.set(.x, from: .keyboard) // iotest samples the mic while X is held
        try await Task.sleep(for: .milliseconds(300))
        #expect(mic.events.withLock { $0 } == ["start"])

        session.stop()
        #expect(mic.events.withLock { $0 } == ["start", "stop"], "closing the game closes the mic")
    }
}

final class FakeRumble: RumbleSink {
    let pulses = Mutex<[Int]>([])
    let stops = Mutex(0)
    func start(milliseconds: Int) { pulses.withLock { $0.append(milliseconds) } }
    func stop() { stops.withLock { $0 += 1 } }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct RumbleAndBlowTests {
    @Test func rumblePakPulsesReachTheSink() async throws {
        let rumble = FakeRumble()
        let session = EmulationSession(rumble: rumble)
        try session.start(rom: romBytes("savetest"), name: "savetest.nds", rumblePak: true)
        try await Task.sleep(for: .milliseconds(300))
        session.stop()
        #expect(rumble.pulses.withLock { $0 } == [16, 16], "savetest flips the motor twice")
        #expect(rumble.stops.withLock { $0 } >= 2)
    }

    @Test func noRumblePakMeansNoPulses() async throws {
        let rumble = FakeRumble()
        let session = EmulationSession(rumble: rumble)
        try session.start(rom: romBytes("savetest"), name: "savetest.nds")
        try await Task.sleep(for: .milliseconds(300))
        session.stop()
        #expect(rumble.pulses.withLock { $0 }.isEmpty)
    }

    @Test func blowingReplacesTheMicrophoneWithTheRecordedBlow() {
        let blow = EmulatorCore.blowSamples
        #expect(blow.count > 1_000)
        let mic = MicrophoneInput()
        var buffer = [Int16](repeating: 0, count: 256)
        #expect(buffer.withUnsafeMutableBufferPointer { mic.read(into: $0) } == 0, "silent when not blowing")

        mic.isBlowing = true
        #expect(buffer.withUnsafeMutableBufferPointer { mic.read(into: $0) } == 256)
        #expect(buffer == Array(blow.prefix(256)))
        _ = buffer.withUnsafeMutableBufferPointer { mic.read(into: $0) }
        #expect(buffer == Array(blow[256..<512]), "playback continues where it left off")
    }

    @Test func blowButtonFitsWithoutOverlapping() throws {
        let container = CGRect(x: 0, y: 0, width: 402, height: 758)
        let layout = GameLayout(container: container, posture: .stacked, displayScale: 3,
                                showsControls: true, showsBlow: true)
        let controls = try #require(layout.controls)
        let blow = try #require(controls.frames[.blow])
        #expect(container.contains(blow))
        for (control, frame) in controls.frames where control != .blow {
            #expect(!frame.intersects(blow), "blow overlaps \(control)")
        }
        #expect(controls.keys(at: CGPoint(x: blow.midX, y: blow.midY)).isEmpty, "blowing is not a button")
        #expect(controls.control(at: CGPoint(x: blow.midX, y: blow.midY)) == .blow)
    }
}
