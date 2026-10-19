// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Testing

/// Drives TestROMs/iotest: touchscreen via the ARM7's TSC reads, a PSG tone while the pen is
/// down, and microphone sampling while X is held.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct IOTests {
    enum Shared {
        static let base: UInt32 = 0x0230_0000
        static let penDown = base + 0x00
        static let rawX = base + 0x04
        static let rawY = base + 0x08
        static let micSample = base + 0x0C
        static let micCount = base + 0x10
        static let arm7Loops = base + 0x14
    }

    let delegate = RecordingDelegate()
    let core: EmulatorCore

    init() throws {
        core = try makeStartedCore(rom: "iotest", delegate: delegate)
        core.run(frames: 10)
        #expect(core.debugRead32(0x0220_0000) == 0xC1A5_5E11, "ARM9 setup must finish")
        #expect(core.debugRead32(Shared.arm7Loops) > 0, "ARM7 loop must be running")
    }

    @Test(arguments: [(0, 0), (100, 50), (128, 96), (255, 191)])
    func touchReachesTouchscreenController(x: Int, y: Int) {
        core.touch(x: x, y: y)
        core.run(frames: 3)
        #expect(core.debugRead32(Shared.penDown) == 1)
        // melonDS reports raw ADC = pixel << 4.
        #expect(core.debugRead32(Shared.rawX) >> 4 == UInt32(x))
        #expect(core.debugRead32(Shared.rawY) >> 4 == UInt32(y))

        core.releaseTouch()
        core.run(frames: 3)
        #expect(core.debugRead32(Shared.penDown) == 0)
    }

    @Test func touchCoordinatesAreClamped() {
        core.touch(x: -40, y: 900)
        core.run(frames: 3)
        #expect(core.debugRead32(Shared.rawX) >> 4 == 0)
        #expect(core.debugRead32(Shared.rawY) >> 4 == 191)
    }

    @Test func touchPaintsTheBottomScreen() throws {
        var frame = ScreenFrame()
        core.run(frames: 1)
        try #require(core.copyFrame(into: &frame))
        let background = frame.bottom[50 * ScreenFrame.width + 100]

        core.touch(x: 100, y: 50)
        core.run(frames: 4)
        try #require(core.copyFrame(into: &frame))
        let painted = frame.bottom[50 * ScreenFrame.width + 100]
        #expect(painted != background)
        #expect(painted & 0xFF > 0xF0 && (painted >> 8) & 0xFF > 0xF0 && (painted >> 16) & 0xFF > 0xF0,
                "painted pixel should be white")
        #expect(frame.bottom[150 * ScreenFrame.width + 200] == background, "untouched area unchanged")
        #expect(Set(frame.top).count == 1, "top screen is the solid backdrop")
    }

    @Test func toneSoundsOnlyWhilePenIsDown() {
        core.run(frames: 5)
        let silent = core.drainAudio()
        #expect(!silent.isEmpty)
        #expect(silent.map { abs(Int($0)) }.max() ?? 0 < 64, "no tone before touching")

        core.touch(x: 10, y: 10)
        core.run(frames: 10)
        let tone = core.drainAudio()
        #expect(tone.map { abs(Int($0)) }.max() ?? 0 > 1_000, "tone should be audible")

        core.releaseTouch()
        core.run(frames: 5)
        _ = core.drainAudio()
        core.run(frames: 10)
        #expect(core.drainAudio().map { abs(Int($0)) }.max() ?? 0 < 64, "tone stops on release")
    }

    @Test func microphoneSamplesComeFromTheDelegate() {
        #expect(delegate.micStarts == 0, "mic must stay closed until the game samples it")

        delegate.micLevel = 16_000
        core.setKeys(.x)
        core.run(frames: 10)

        #expect(delegate.micStarts > 0)
        #expect(delegate.micReads > 0)
        #expect(core.debugRead32(Shared.micCount) > 0)
        // TSC mic channel: unsigned 12-bit = (sample ^ 0x8000) >> 4.
        #expect(core.debugRead32(Shared.micSample) == UInt32((UInt16(16_000) ^ 0x8000) >> 4))
    }
}
