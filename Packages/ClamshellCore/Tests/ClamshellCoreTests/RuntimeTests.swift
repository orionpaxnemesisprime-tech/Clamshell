// SPDX-License-Identifier: GPL-3.0-or-later

@testable import ClamshellCore
import CoreGraphics
import Foundation
import Testing

@Suite struct FrameStoreTests {
    @Test func readerSeesOnlyNewerCompleteFrames() {
        let store = FrameStore()
        #expect(store.withLatestFrame { _, _, _ in true } == nil, "nothing published yet")

        store.publish { top, bottom in
            top.update(repeating: 1, count: ScreenFrame.pixelCount)
            bottom.update(repeating: 2, count: ScreenFrame.pixelCount)
            return true
        }
        let first = store.withLatestFrame { top, bottom, generation in (top[0], bottom.last!, generation) }
        #expect(first?.0 == 1 && first?.1 == 2 && first?.2 == 1)
        #expect(store.withLatestFrame(newerThan: 1) { _, _, _ in true } == nil)
    }

    @Test func discardedPublishKeepsPreviousFrame() {
        let store = FrameStore()
        store.publish { top, _ in top[0] = 7; return true }
        store.publish { _, _ in false }
        #expect(store.generation == 1)
        #expect(store.withLatestFrame { top, _, _ in top[0] } == 7)
    }

    @Test func writerNeverTouchesTheSlotBeingRead() {
        let store = FrameStore()
        store.publish { top, _ in top.update(repeating: 1, count: ScreenFrame.pixelCount); return true }
        store.withLatestFrame { top, _, _ in
            // Publishing twice while reading must use the other two slots.
            for value: UInt32 in [2, 3] {
                store.publish { newTop, _ in
                    #expect(newTop != UnsafeMutablePointer(mutating: top.baseAddress!))
                    newTop.update(repeating: value, count: ScreenFrame.pixelCount)
                    return true
                }
            }
            #expect(top.allSatisfy { $0 == 1 }, "frame being read stays intact")
        }
        #expect(store.withLatestFrame { top, _, _ in top[0] } == 3)
    }
}

@Suite struct AudioRingBufferTests {
    private func read(_ ring: AudioRingBuffer, frames: Int) -> (left: [Float], right: [Float], real: Int) {
        var left = [Float](repeating: -9, count: frames)
        var right = [Float](repeating: -9, count: frames)
        let real = left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in ring.read(left: l.baseAddress!, right: r.baseAddress!, frames: frames) }
        }
        return (left, right, real)
    }

    @Test func roundTripsInterleavedStereo() {
        let ring = AudioRingBuffer(capacityFrames: 16)
        let samples: [Int16] = [16_384, -16_384, 32_767, 0]
        #expect(ring.write(samples, frames: 2) == 2)
        let out = read(ring, frames: 2)
        #expect(out.real == 2)
        #expect(out.left == [0.5, 32_767 / 32_768])
        #expect(out.right == [-0.5, 0])
        #expect(ring.framesAvailable == 0)
    }

    @Test func underflowPadsWithSilence() {
        let ring = AudioRingBuffer(capacityFrames: 16)
        ring.write([100, 100], frames: 1)
        let out = read(ring, frames: 4)
        #expect(out.real == 1)
        #expect(out.left.dropFirst().allSatisfy { $0 == 0 })
        #expect(ring.underflows == 1)
    }

    @Test func overflowDropsNewestAndWrapsCorrectly() {
        let ring = AudioRingBuffer(capacityFrames: 4, maxLatencyFrames: 4)
        let six = (0..<12).map { Int16($0) }
        #expect(ring.write(six, frames: 6) == 4)
        _ = read(ring, frames: 3)
        #expect(ring.write([100, 101, 102, 103], frames: 2) == 2) // wraps around the end
        let out = read(ring, frames: 3)
        #expect(out.left.map { Int16($0 * 32_768) } == [6, 100, 102])
    }

    @Test func readsBoundLatency() {
        let ring = AudioRingBuffer(capacityFrames: 64, maxLatencyFrames: 8)
        let samples = (0..<64).map { Int16($0) }
        ring.write(samples, frames: 32)
        let out = read(ring, frames: 1)
        // Oldest frames are skipped so at most 8 remain queued before this read.
        #expect(Int16(out.left[0] * 32_768) == 48)
        #expect(ring.framesAvailable == 7)
    }
}

@Suite struct ScreenLayoutTests {
    static let phone = CGRect(x: 0, y: 0, width: 400, height: 840)

    private func expectValid(_ layout: ScreenLayout, in container: CGRect) {
        #expect(layout.top.size == layout.bottom.size, "both screens share one scale")
        #expect(abs(layout.top.width / layout.top.height - 4.0 / 3.0) < 0.001)
        #expect(!layout.top.intersects(layout.bottom))
        #expect(container.contains(layout.top) && container.contains(layout.bottom))
        #expect(layout.top.width > 0)
    }

    @Test func clamshellKeepsScreensOffTheFold() {
        let fold = CGRect(x: 0, y: 410, width: 400, height: 20)
        let layout = ScreenLayout(container: Self.phone, posture: .clamshell(fold: fold), displayScale: 3)
        expectValid(layout, in: Self.phone)
        #expect(layout.top.maxY <= fold.minY)
        #expect(layout.bottom.minY >= fold.maxY)
        #expect(layout.top.minY < layout.bottom.minY, "top screen above the fold")
    }

    @Test func clamshellWithVerticalFoldSplitsLeftRight() {
        let container = CGRect(x: 0, y: 0, width: 840, height: 400)
        let fold = CGRect(x: 410, y: 0, width: 20, height: 400)
        let layout = ScreenLayout(container: container, posture: .clamshell(fold: fold), displayScale: 3)
        expectValid(layout, in: container)
        #expect(layout.top.maxX <= fold.minX && layout.bottom.minX >= fold.maxX)
    }

    @Test(arguments: [ScreenPosture.stacked, .sideBySide])
    func openPosturesFit(_ posture: ScreenPosture) {
        let container = posture == .stacked ? Self.phone : CGRect(x: 0, y: 0, width: 840, height: 400)
        expectValid(ScreenLayout(container: container, posture: posture, displayScale: 3), in: container)
    }

    @Test func integerScalesWhenThereIsRoom() {
        let layout = ScreenLayout(container: Self.phone, posture: .stacked, displayScale: 3)
        let pixelScale = layout.top.width * 3 / 256
        #expect(pixelScale == pixelScale.rounded())
    }

    @Test func tinyContainersStillFit() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        expectValid(ScreenLayout(container: tiny, posture: .stacked, displayScale: 1), in: tiny)
    }

    @Test func touchMapsCornersAndRejectsOutside() throws {
        let layout = ScreenLayout(top: CGRect(x: 0, y: 0, width: 512, height: 384),
                                  bottom: CGRect(x: 0, y: 400, width: 512, height: 384))
        #expect(layout.touchLocation(at: CGPoint(x: 10, y: 10)) == nil, "top screen is not touchable")
        let origin = try #require(layout.touchLocation(at: CGPoint(x: 0, y: 400)))
        #expect(origin == (0, 0))
        let middle = try #require(layout.touchLocation(at: CGPoint(x: 200, y: 500)))
        #expect(middle == (100, 50))
        let corner = try #require(layout.touchLocation(at: CGPoint(x: 511.9, y: 783.9)))
        #expect(corner == (255, 191))
        #expect(layout.clampedTouchLocation(at: CGPoint(x: -50, y: 2_000)) == (0, 191))
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct EmulationSessionTests {
    private func rom(_ name: String) throws -> [UInt8] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "nds", subdirectory: "ROMs"))
        return Array(try Data(contentsOf: url))
    }

    @Test func runsAtTheHandheldFrameRate() throws {
        let session = EmulationSession()
        try session.start(rom: rom("iotest"), name: "iotest.nds")
        defer { session.stop() }
        Thread.sleep(forTimeInterval: 2.2)
        let stats = session.statistics
        #expect(abs(stats.framesPerSecond - EmulatorCore.frameRate) < 2, "paced at ~59.83 fps, got \(stats.framesPerSecond)")
        #expect(stats.framesRun > 120 && stats.framesRun < 140)
        #expect(session.frames.generation == stats.framesRun)
        #expect(session.audio.framesAvailable > 0, "audio flows into the ring")
    }

    @Test func touchAndPauseReachTheThread() throws {
        let session = EmulationSession()
        try session.start(rom: rom("iotest"), name: "iotest.nds")
        defer { session.stop() }
        Thread.sleep(forTimeInterval: 0.3)

        session.touch(x: 100, y: 50)
        Thread.sleep(forTimeInterval: 0.2)
        let painted = try #require(session.frames.withLatestFrame { _, bottom, _ in bottom[50 * 256 + 100] })
        // melonDS expands 5-bit white to 0xFB per channel.
        #expect([0, 8, 16].allSatisfy { (painted >> $0) & 0xFF > 0xF0 }, "touch painted a white dot")
        session.releaseTouch()

        session.isPaused = true
        Thread.sleep(forTimeInterval: 0.1)
        let pausedAt = session.statistics.framesRun
        Thread.sleep(forTimeInterval: 0.3)
        #expect(session.statistics.framesRun == pausedAt)
        session.isPaused = false
        Thread.sleep(forTimeInterval: 0.2)
        #expect(session.statistics.framesRun > pausedAt)
    }

    @Test func stopJoinsAndRestartWorks() throws {
        let session = EmulationSession()
        try session.start(rom: rom("iotest"), name: "iotest.nds")
        Thread.sleep(forTimeInterval: 0.1)
        session.stop()
        #expect(!session.isRunning)
        try session.start(rom: rom("smoketest"), name: "smoketest.nds")
        Thread.sleep(forTimeInterval: 0.2)
        #expect(session.isRunning)
        session.stop()
        #expect(!session.isRunning)
    }

    @Test func invalidROMThrowsWithoutStartingAThread() {
        let session = EmulationSession()
        #expect(throws: EmulatorError.invalidROM) {
            try session.start(rom: [0, 1, 2], name: "bad.nds")
        }
        #expect(!session.isRunning)
    }
}
