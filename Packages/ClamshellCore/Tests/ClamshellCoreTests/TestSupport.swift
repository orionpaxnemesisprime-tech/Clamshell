// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Testing

/// Creates a core, loads `ROMs/<name>.nds` from the test bundle and starts it.
func makeStartedCore(rom name: String, delegate: EmulatorCoreDelegate? = nil) throws -> EmulatorCore {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "nds", subdirectory: "ROMs"))
    let core = EmulatorCore()
    core.delegate = delegate
    try core.loadROM(Array(try Data(contentsOf: url)), name: "\(name).nds")
    core.start()
    return core
}

extension EmulatorCore {
    func run(frames: Int) {
        for _ in 0..<frames { runFrame() }
    }

    /// Reads and returns all buffered audio as interleaved stereo samples.
    func drainAudio() -> [Int16] {
        var samples: [Int16] = []
        var chunk = [Int16](repeating: 0, count: 4096)
        while true {
            let frames = chunk.withUnsafeMutableBufferPointer { readAudio(into: $0) }
            if frames == 0 { break }
            samples.append(contentsOf: chunk[0..<(frames * 2)])
        }
        return samples
    }
}

/// Records delegate calls and feeds a constant microphone level.
final class RecordingDelegate: EmulatorCoreDelegate {
    var micLevel: Int16 = 0
    private(set) var micStarts = 0
    private(set) var micReads = 0

    func emulatorCoreDidStartMicrophone(_ core: EmulatorCore) { micStarts += 1 }

    func emulatorCore(_ core: EmulatorCore, readMicrophoneInto buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        micReads += 1
        buffer.update(repeating: micLevel)
        return buffer.count
    }
}
