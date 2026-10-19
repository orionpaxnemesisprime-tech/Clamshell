// SPDX-License-Identifier: GPL-3.0-or-later

import Synchronization

/// Lock-free single-producer / single-consumer ring of interleaved stereo `Int16` frames.
///
/// The emulation thread writes; the real-time audio thread reads. Reading never locks,
/// allocates or blocks, so it is safe inside an `AVAudioSourceNode` render block.
public final class AudioRingBuffer: @unchecked Sendable {
    // @unchecked: storage is shared, but the producer only writes [write, read + capacity)
    // and the consumer only reads [read, write); indices are published with acquire/release.

    public let capacityFrames: Int
    /// Reads keep at most this many frames queued, dropping older audio to bound latency.
    public let maxLatencyFrames: Int

    private let storage: UnsafeMutablePointer<Int16>
    private let mask: Int
    private let writeIndex = Atomic<Int>(0) // total frames written
    private let readIndex = Atomic<Int>(0)  // total frames consumed
    private let underflowCount = Atomic<Int>(0)

    /// `capacityFrames` is rounded up to a power of two.
    public init(capacityFrames: Int = 8_192, maxLatencyFrames: Int = 4_800) {
        var capacity = 1
        while capacity < capacityFrames { capacity <<= 1 }
        self.capacityFrames = capacity
        self.maxLatencyFrames = min(maxLatencyFrames, capacity)
        mask = capacity - 1
        storage = .allocate(capacity: capacity * 2)
        storage.initialize(repeating: 0, count: capacity * 2)
    }

    deinit {
        storage.deallocate()
    }

    public var framesAvailable: Int {
        writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .acquiring)
    }

    /// Number of reads that could not be fully satisfied.
    public var underflows: Int { underflowCount.load(ordering: .relaxed) }

    /// Producer. Writes up to `frames` interleaved frames; drops what doesn't fit.
    @discardableResult
    public func write(_ samples: UnsafePointer<Int16>, frames: Int) -> Int {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let count = min(frames, capacityFrames - (write - read))
        guard count > 0 else { return 0 }
        for i in 0..<count {
            let slot = ((write + i) & mask) * 2
            storage[slot] = samples[i * 2]
            storage[slot + 1] = samples[i * 2 + 1]
        }
        writeIndex.store(write + count, ordering: .releasing)
        return count
    }

    /// Consumer. Fills `left`/`right` with `frames` samples in -1...1, padding with silence.
    /// Returns the number of real (non-padded) frames.
    @discardableResult
    public func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        let write = writeIndex.load(ordering: .acquiring)
        var read = readIndex.load(ordering: .relaxed)
        if write - read > maxLatencyFrames {
            read = write - maxLatencyFrames
        }
        let count = min(frames, write - read)
        let scale: Float = 1 / 32_768
        for i in 0..<count {
            let slot = ((read + i) & mask) * 2
            left[i] = Float(storage[slot]) * scale
            right[i] = Float(storage[slot + 1]) * scale
        }
        if count < frames {
            (left + count).update(repeating: 0, count: frames - count)
            (right + count).update(repeating: 0, count: frames - count)
            underflowCount.add(1, ordering: .relaxed)
        }
        readIndex.store(read + count, ordering: .releasing)
        return count
    }

    /// Consumer. Discards everything queued.
    public func flush() {
        readIndex.store(writeIndex.load(ordering: .acquiring), ordering: .releasing)
    }
}
