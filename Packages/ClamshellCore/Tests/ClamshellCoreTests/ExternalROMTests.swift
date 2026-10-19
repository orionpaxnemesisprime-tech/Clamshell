// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Testing

/// Smoke test for a real homebrew game kept *outside* the repo. Only runs when
/// `CLAMSHELL_EXTERNAL_ROM` points at a file, so third-party ROMs are never committed:
///
///     CLAMSHELL_EXTERNAL_ROM=/path/to/game.nds swift test --filter ExternalROMTests
///
/// Only use open-source homebrew you have the right to use (see app-store-compliance).
@Suite(.serialized, .timeLimit(.minutes(2)),
       .enabled(if: ProcessInfo.processInfo.environment["CLAMSHELL_EXTERNAL_ROM"] != nil))
struct ExternalROMTests {
    @Test func bootsAndDrawsBothScreens() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CLAMSHELL_EXTERNAL_ROM"])
        let rom = Array(try Data(contentsOf: URL(filePath: path)))
        let sdCard = FileManager.default.temporaryDirectory.appending(path: "clamshell-external-sd-\(UUID()).img")
        defer {
            try? FileManager.default.removeItem(at: sdCard)
            try? FileManager.default.removeItem(at: sdCard.appendingPathExtension("idx"))
        }
        let name = URL(filePath: path).lastPathComponent
        for attempt in ["fresh SD image", "existing SD image"] {
            let start = ContinuousClock.now
            try EmulatorCore().loadROM(rom, name: name, sdCard: sdCard)
            print("External ROM: load with \(attempt) took \(ContinuousClock.now - start)")
        }
        let core = EmulatorCore()
        try core.loadROM(rom, name: name, sdCard: sdCard)
        core.start()

        // Ten emulated seconds: long enough for most homebrew to reach its title screen.
        let frames = 600
        let clock = ContinuousClock()
        let elapsed = clock.measure { core.run(frames: frames) }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let fps = Double(frames) / seconds
        print("External ROM: \(frames) frames in \(String(format: "%.2f", seconds)) s = \(Int(fps)) fps "
              + "(\(String(format: "%.1f", fps / EmulatorCore.frameRate))x realtime)")
        #expect(core.isRunning, "the game must not have stopped the console")

        var frame = ScreenFrame()
        try #require(core.copyFrame(into: &frame))
        let topColours = Set(frame.top.map { $0 & 0xFFFFFF }).count
        let bottomColours = Set(frame.bottom.map { $0 & 0xFFFFFF }).count
        print("External ROM: top screen \(topColours) colours, bottom screen \(bottomColours) colours")
        #expect(topColours + bottomColours > 2, "something beyond a blank fill is on screen")

        if let png = frame.pngData() {
            let out = FileManager.default.temporaryDirectory.appending(path: "clamshell-external-rom.png")
            try png.write(to: out)
            print("External ROM: screenshot at \(out.path(percentEncoded: false))")
        }
    }
}
