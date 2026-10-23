// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Testing

/// Boots TestROMs/smoketest (built from source by Scripts/make-test-rom.py) headlessly.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SmokeTests {
    static let setupDone: UInt32 = 0xC1A5_5E11
    static let resultAddress: UInt32 = 0x0220_0000

    let core: EmulatorCore

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "smoketest", withExtension: "nds",
                                                 subdirectory: "ROMs"))
        core = EmulatorCore()
        try core.loadROM(Array(try Data(contentsOf: url)), name: "smoketest.nds")
        core.start()
    }

    private func run(frames: Int) {
        for _ in 0..<frames { core.runFrame() }
    }

    @Test func bootsAndSignalsSetupDone() {
        run(frames: 10)
        #expect(core.debugRead32(Self.resultAddress) == Self.setupDone)
        #expect(core.debugRead32(Self.resultAddress + 8) > 0, "ARM9 main loop should be running")
    }

    @Test func framebuffersHaveExpectedColoursInBGRAOrder() throws {
        run(frames: 10)
        var frame = ScreenFrame()
        try #require(core.copyFrame(into: &frame))

        func channels(_ pixel: UInt32) -> (r: UInt32, g: UInt32, b: UInt32) {
            ((pixel >> 16) & 0xFF, (pixel >> 8) & 0xFF, pixel & 0xFF)
        }

        // Top screen pixel i = BGR555 value i: pixel 0 black, pixel 31 pure red.
        let black = channels(frame.top[0])
        #expect(black.r == 0 && black.g == 0 && black.b == 0)
        let red = channels(frame.top[31])
        #expect(red.r > 0xF0 && red.g == 0 && red.b == 0)
        #expect(Set(frame.top).count > 1_000, "top screen should show the gradient")

        // Bottom screen: uniform blue backdrop.
        let blue = channels(frame.bottom[0])
        #expect(blue.b > 0xF0 && blue.r == 0 && blue.g == 0)
        #expect(Set(frame.bottom).count == 1)
    }

    @Test func keyMaskReachesKeyInputActiveLow() {
        run(frames: 10)
        #expect(core.debugRead32(Self.resultAddress) == Self.setupDone, "ROM must reach its main loop")

        core.setKeys([.a, .start])
        run(frames: 2)
        let keyInput = core.debugRead32(Self.resultAddress + 4) & 0x3FF
        // Active-low: A (bit 0) and Start (bit 3) clear, all other buttons set.
        #expect(keyInput == 0x3FF & ~UInt32(0b1001))

        core.setKeys([])
        run(frames: 2)
        #expect(core.debugRead32(Self.resultAddress + 4) & 0x3FF == 0x3FF)
    }

    @Test func saveStateRoundTripRestoresMachine() throws {
        run(frames: 10)
        let state = try core.saveState()
        let counterAtSave = core.debugRead32(Self.resultAddress + 8)

        run(frames: 30)
        #expect(core.debugRead32(Self.resultAddress + 8) != counterAtSave)

        try core.loadState(state)
        #expect(core.debugRead32(Self.resultAddress + 8) == counterAtSave)
    }

    @Test func corruptStateIsRejectedAndMachineUntouched() {
        run(frames: 10)
        let counter = core.debugRead32(Self.resultAddress + 8)
        #expect(throws: EmulatorError.loadStateFailed) {
            try core.loadState(Array(repeating: 0xAB, count: 4096))
        }
        #expect(core.debugRead32(Self.resultAddress + 8) == counter)
    }

    @Test func lidCloseIsReported() {
        core.isLidClosed = true
        #expect(core.isLidClosed)
        core.isLidClosed = false
        #expect(!core.isLidClosed)
    }

    @Test func invalidROMIsRejected() {
        let fresh = EmulatorCore()
        #expect(throws: EmulatorError.invalidROM) {
            try fresh.loadROM(Array(repeating: 0, count: 64))
        }
    }

    /// Interpreter speed on this machine. Logged, not asserted: hosts vary.
    @Test func interpreterThroughput() {
        let frames = 600
        let clock = ContinuousClock()
        let elapsed = clock.measure { run(frames: frames) }
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let fps = Double(frames) / seconds
        print("ClamshellCore: \(frames) frames in \(String(format: "%.2f", seconds)) s = "
              + "\(Int(fps)) fps (\(String(format: "%.1f", fps / EmulatorCore.frameRate))x realtime)")
        #expect(fps > 0)
    }
}
