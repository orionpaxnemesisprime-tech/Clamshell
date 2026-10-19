// SPDX-License-Identifier: GPL-3.0-or-later

import Synchronization

/// Supplies microphone samples to the emulated console.
///
/// `start`/`stop` are called on the emulation thread when the game opens or closes the mic;
/// implementations must return quickly (hop to another thread for real work). `read` is
/// called on the emulation thread and must never block.
public protocol MicrophoneSource: AnyObject, Sendable {
    func start()
    func stop()
    /// Fills `buffer` with signed 16-bit mono samples at `EmulatorCore.microphoneSampleRate`;
    /// returns how many were written.
    func read(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int
}

extension EmulatorCore {
    /// The rate melonDS consumes microphone samples at (Hz).
    public static let microphoneSampleRate = 47_743.4659091
}

/// Lock-free single-producer / single-consumer ring of mono `Int16` samples.
public final class MonoSampleRing: @unchecked Sendable {
    // @unchecked: storage is shared, but the producer only writes free slots and the consumer
    // only reads filled ones; indices are published with acquire/release ordering.

    public let capacity: Int
    private let storage: UnsafeMutablePointer<Int16>
    private let mask: Int
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    public init(capacity requested: Int = 16_384) {
        var capacity = 1
        while capacity < requested { capacity <<= 1 }
        self.capacity = capacity
        mask = capacity - 1
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    public var count: Int { writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .acquiring) }

    /// Producer. Drops the oldest samples' worth of new input that doesn't fit.
    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Int16>) -> Int {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let n = min(samples.count, capacity - (write - read))
        for i in 0..<n { storage[(write + i) & mask] = samples[i] }
        writeIndex.store(write + n, ordering: .releasing)
        return n
    }

    /// Consumer.
    public func read(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        let write = writeIndex.load(ordering: .acquiring)
        let read = readIndex.load(ordering: .relaxed)
        let n = min(buffer.count, write - read)
        for i in 0..<n { buffer[i] = storage[(read + i) & mask] }
        readIndex.store(read + n, ordering: .releasing)
        return n
    }

    /// Consumer. Discards everything queued.
    public func flush() {
        readIndex.store(writeIndex.load(ordering: .acquiring), ordering: .releasing)
    }
}
