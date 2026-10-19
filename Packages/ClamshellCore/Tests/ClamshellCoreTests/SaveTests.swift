// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Synchronization
import Testing

/// TestROMs/savetest keeps a boot counter in a 64 Kbit EEPROM.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SaveTests {
    static let bootCount: UInt32 = 0x0220_0010

    final class SaveRecorder: EmulatorCoreDelegate {
        var writes: [(memory: [UInt8], range: Range<Int>)] = []
        func emulatorCore(_ core: EmulatorCore, didWriteSave saveMemory: UnsafeRawBufferPointer, range: Range<Int>) {
            writes.append((Array(saveMemory), range))
        }
    }

    private func rom() throws -> [UInt8] {
        let url = try #require(Bundle.module.url(forResource: "savetest", withExtension: "nds", subdirectory: "ROMs"))
        return Array(try Data(contentsOf: url))
    }

    private func boot(save: [UInt8]?) throws -> (core: EmulatorCore, recorder: SaveRecorder) {
        let core = EmulatorCore()
        let recorder = SaveRecorder()
        core.delegate = recorder
        try core.loadROM(rom(), save: save, name: "savetest.nds")
        core.start()
        core.run(frames: 10)
        #expect(core.debugRead32(0x0220_0000) == 0xC1A5_5E11, "ROM finished its save routine")
        return (core, recorder)
    }

    @Test func gameWritesAreReportedAndPersistAcrossBoots() throws {
        let first = try boot(save: nil)
        #expect(first.core.saveMemory()?.count == 8_192, "unknown cartridges get a 64 Kbit EEPROM")
        #expect(first.core.debugRead32(Self.bootCount) == 0, "blank EEPROM reads as first boot")
        let write = try #require(first.recorder.writes.last)
        #expect(write.range == 0..<1)
        #expect(write.memory[0] == 1)

        let second = try boot(save: write.memory)
        #expect(second.core.debugRead32(Self.bootCount) == 1, "save loaded into the cartridge")
        #expect(second.recorder.writes.last?.memory[0] == 2)
    }

    @Test func sessionDebouncesSavesAndFlushesOnStop() throws {
        let saves = Mutex<[[UInt8]]>([])
        let session = EmulationSession()

        try session.start(rom: rom(), name: "savetest.nds", saveDebounce: .milliseconds(300)) { memory in
            saves.withLock { $0.append(memory) }
        }
        Thread.sleep(forTimeInterval: 0.1)
        #expect(saves.withLock { $0.isEmpty }, "nothing is handed over before the debounce")
        Thread.sleep(forTimeInterval: 0.5)
        #expect(saves.withLock { $0.count } == 1)
        session.stop()
        #expect(saves.withLock { $0.count } == 1, "no redundant flush when nothing changed")

        try session.start(rom: rom(), save: saves.withLock { $0[0] }, name: "savetest.nds",
                          saveDebounce: .seconds(60)) { memory in
            saves.withLock { $0.append(memory) }
        }
        Thread.sleep(forTimeInterval: 0.2)
        session.stop()
        let all = saves.withLock { $0 }
        #expect(all.count == 2, "pending save flushed on stop")
        #expect(all.last?[0] == 2)
    }

    @Test func storeRoundTripsAndKeepsABackup() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "clamshell-saves-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SaveStore(directory: directory)
        let id = SaveStore.identifier(for: try rom())
        #expect(id.count == 40 && id.allSatisfy(\.isHexDigit))

        #expect(store.load(identifier: id) == nil)
        try store.write([1, 2, 3], identifier: id)
        try store.write([4, 5, 6], identifier: id)
        #expect(store.load(identifier: id) == [4, 5, 6])
        #expect(try Data(contentsOf: store.backupURL(for: id)) == Data([1, 2, 3]))

        try store.write([4, 5, 6], identifier: id) // unchanged: backup must not be clobbered
        #expect(try Data(contentsOf: store.backupURL(for: id)) == Data([1, 2, 3]))
    }
}
